# Running multiple Hivemind stacks on one host

Several Hivemind stacks on one machine is a supported, intended arrangement.
This document is the contract that makes it safe: what each stack is allowed
to consume, how to tune the host, and how to tell which stack is misbehaving.

The short version: **a stack's outbound concurrency is a budget, not a
preference.** Every stack draws from one shared, finite host resource, and the
sum of the budgets must stay under host capacity.

---

## 1. The shared resource

A TCP connection needs a local (ephemeral) source port. macOS ships with:

| sysctl                         | default | meaning                       |
| ------------------------------ | ------- | ----------------------------- |
| `net.inet.ip.portrange.first`  | 49152   | first ephemeral port          |
| `net.inet.ip.portrange.last`   | 65535   | last ephemeral port           |
| `net.inet.tcp.msl`             | 15000   | TIME_WAIT = 2 × MSL = **30s** |

That is **16,384 ports**, and a closed connection holds its port in
`TIME_WAIT` for 30 seconds before the kernel can reuse it. So the sustainable
steady-state connection rate for the whole machine is roughly:

```
16,384 ports / 30 s  ≈  545 new connections per second, host-wide
```

**Docker Desktop on macOS routes container egress through the host's own
sockets** (`com.docker.backend`). Container connections are host connections.
There is no per-container pool. This is the coupling that matters: a runaway
loop inside one container exhausts the pool for the entire machine, including
software that has nothing to do with Hivemind.

When the pool is empty, `connect()` fails instantly with `EADDRNOTAVAIL`
("Can't assign requested address") — before a packet leaves the box. It looks
like a network outage and is not one.

### What happened on 2026-08-24

One stack retried a permanently-failing Anthropic call (`400 "You're out of
extra usage"`) with no cap and no backoff for 40 hours, at roughly 700
connections per second. TIME_WAIT reached **20,775** against a 16,384-port
pool. Every process on the Mac mini lost outbound networking. The container
reported `restarts=0` the whole time and nothing alerted.

Full write-up: `HANDOFF-PORT-EXHAUSTION.md`.

---

## 2. Host tuning (do this once, per host)

Widening the range and shortening TIME_WAIT raises the ceiling from ~16k to
~49k concurrent outbound sockets and frees each one 15× faster:

```
16,384 → 49,152 ports,  TIME_WAIT 30s → 2s
≈ 24,500 connections per second, host-wide
```

Install the LaunchDaemon so it survives reboot:

```bash
sudo cp scripts/hivemind-host-tuning.plist \
        /Library/LaunchDaemons/com.hivemind.host-tuning.plist
sudo chown root:wheel /Library/LaunchDaemons/com.hivemind.host-tuning.plist
sudo chmod 644        /Library/LaunchDaemons/com.hivemind.host-tuning.plist
sudo launchctl load -w /Library/LaunchDaemons/com.hivemind.host-tuning.plist

# verify
sysctl net.inet.ip.portrange.first net.inet.tcp.msl
# expect: 16384 and 1000
```

> **This is headroom, not a fix.** A stack retrying without bound will exhaust
> 49k ports too; it just takes longer. The tuning buys time for the per-stack
> ceilings below to do the actual work.

---

## 3. The per-stack budget

Each stack declares its share in its `.env`. Defaults live in
`docker-compose.yml`.

| Variable                      | Default  | What it bounds                                              |
| ----------------------------- | -------- | ----------------------------------------------------------- |
| `SDK_PROXY_MAX_CONCURRENCY`   | `4`      | Provider calls in flight at once. Each spawns one Claude Code subprocess. |
| `SDK_PROXY_MAX_QUEUE`         | `16`     | Callers allowed to wait for a slot. Beyond this, requests are shed with `429`. |
| `SDK_PROXY_CIRCUIT_THRESHOLD` | `3`      | Consecutive permanent failures before the credential stops being dialled. |
| `SDK_PROXY_CIRCUIT_OPEN_MS`   | `900000` | How long the circuit stays open (15 min) before one probe. |
| `PROVIDER_CIRCUIT_THRESHOLD`  | `3`      | Same, on the Rails side (shared across workers via Redis).  |
| `PROVIDER_CIRCUIT_OPEN_SECONDS` | `900`  | Rails-side cooldown.                                        |

### Budget arithmetic

A single in-flight OAuth request is not one connection. The Claude Code
subprocess runs its own retry ladder — **up to 10 attempts, each on a new TCP
connection** — plus MCP tool traffic. Budget conservatively:

```
peak sockets per stack ≈ SDK_PROXY_MAX_CONCURRENCY × 10
```

With the tuned host (~49k ports, 2s TIME_WAIT):

| Stacks on host | `SDK_PROXY_MAX_CONCURRENCY` each | Peak sockets | Headroom  |
| -------------- | -------------------------------- | ------------ | --------- |
| 1              | 8                                | ~80          | enormous  |
| 2              | 4 (default)                      | ~80          | enormous  |
| 4              | 4                                | ~160         | large     |
| 8              | 2                                | ~160         | large     |

The ceilings are deliberately far below what the pool can carry. The pool was
never exhausted by legitimate concurrency — it was exhausted by an unbounded
retry loop. The ceiling exists so that a *bug* cannot consume the host, not to
ration normal work. Raise `SDK_PROXY_MAX_CONCURRENCY` if a stack is genuinely
throughput-bound; keep the sum across stacks under ~64.

### Rule

```
sum(SDK_PROXY_MAX_CONCURRENCY across all stacks on the host) × 10  <  pool size / 4
```

---

## 4. What stops a runaway, and where

Four independent bounds, innermost first. Each one alone would have prevented
the outage; together they make it structurally impossible.

1. **Error classification** — `sdk-proxy/error-classifier.js` and
   `app/services/providers/error_classifier.rb`. A `400 "out of extra usage"`
   is `retryable: false`. Anything unclassifiable also defaults to
   **permanent**: treating the unknown as retryable is what caused the outage.

2. **Per-credential circuit breaker** — `sdk-proxy/circuit-breaker.js` (in
   process) and `Providers::CircuitBreaker` (Redis, shared by every Sidekiq
   worker and Puma process in the stack). After
   `SDK_PROXY_CIRCUIT_THRESHOLD` consecutive permanent failures the circuit
   opens and **no socket is opened at all** — no DNS, no connect, no port
   consumed. One exhausted account never silences a healthy one.

3. **Bounded work queue** — `sdk-proxy/concurrency.js`. Never more than
   `SDK_PROXY_MAX_CONCURRENCY` subprocesses; overflow is shed with `429`
   rather than spawned.

4. **Bounded job retries** — `app/jobs/application_job.rb`.
   `discard_on PermanentProviderError` (never retry a quota failure) and
   `retry_on TransientProviderError, attempts: 3` with exponential backoff.
   Nothing inherits Sidekiq's default of 25 any more.

---

## 5. Observability

### The one number to watch

```bash
scripts/port-pressure-canary.sh              # human
scripts/port-pressure-canary.sh --json       # for a monitor
scripts/port-pressure-canary.sh --watch 60   # loop
```

Exit codes: `0` ok, `1` warning (TIME_WAIT ≥ 8,000), `2` critical (≥ 14,000).
Thresholds override with `PORT_CANARY_WARN` / `PORT_CANARY_CRIT`.

Run it from cron on any host carrying more than one stack:

```cron
*/5 * * * * /path/to/hivemind/scripts/port-pressure-canary.sh --json >> /var/log/hivemind-ports.log 2>&1
```

### Per-stack health

```bash
# every sdk-proxy on the box, with its circuit state and in-flight count
docker ps --format '{{.Names}}' | grep sdk-proxy | while read -r c; do
  echo "== $c"; docker exec "$c" wget -qO- http://localhost:3003/health; echo
done
```

A healthy proxy reports `"degraded": false` and an empty `circuits` array. A
degraded one names the credential and the reason:

```json
{
  "status": "ok",
  "degraded": true,
  "reason": "provider circuit open: quota_exhausted",
  "concurrency": { "inflight": 0, "queued": 0, "max_concurrent": 4, "total_shed": 0 },
  "circuits": [
    { "credential": "a1b2c3d4e5f6", "state": "open", "reason": "quota_exhausted",
      "consecutive_failures": 3, "opened_at": "2026-08-25T09:00:00.000Z" }
  ]
}
```

Note the Docker `HEALTHCHECK` stays green while a circuit is open. That is
deliberate: the process is alive and correctly refusing to dial. Restarting it
would only reset the circuit and resume the churn.

### Rails-side health

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/system/provider_health | jq
```

Returns `503` when degraded, and distinguishes the two failures that looked
identical during the incident:

- `"reason": "provider circuit open: quota_exhausted"` — the provider refused us.
- `"can_open_sockets": false` — **the host cannot bind a socket at all.** This
  is the port-exhaustion signature. Do not chase the provider; check the canary.

### In the UI

An open circuit renders a red banner on every page naming the provider, the
reason, when it opened, and what to do about it — with a **Retry now** button
that clears the circuit after a human fixes the account. Editing a provider's
credential clears its circuit automatically.

### In the logs

One line, greppable across all stacks:

```bash
docker compose logs --since 24h | grep ALARM
```

```
[ALARM][CircuitBreaker] provider circuit OPEN provider=anthropic credential=a1b2c3d4e5f6
  reason=quota_exhausted — no further outbound calls will be made on this
  credential until a human acts.
```

### Proving it, on a real host

CI covers the bounds as units (`sdk-proxy/__tests__/guard.test.js`,
`spec/services/providers/resource_discipline_spec.rb`). What CI cannot prove
is the part that actually broke: that a runaway inside one container does not
consume the *host's* port pool. That needs real Docker and real sockets:

```bash
scripts/multi-stack-fault-drill.sh <faulty-stack> <healthy-stack> [seconds]

# e.g. drive the parents stack against a permanently-invalid credential for
# 10 minutes and assert the other stack and the host are unaffected
scripts/multi-stack-fault-drill.sh hivemind-parents hivemind 600
```

It asserts host `TIME_WAIT` stays under `TIME_WAIT_CEILING` (default 2,000),
that the faulty stack's attempts are bounded and countable, that it reports
`degraded: true` with the real reason, that the sibling stack keeps serving,
and that the host can still open outbound sockets. Run it after changing any
ceiling, and after upgrading the Agent SDK.

---

## 6. Isolation between stacks

Verified as of 2026-08-25. Docker Compose scopes these by project name
(`-p hivemind`, `-p hivemind-parents`), so they are **isolated**:

- Containers, networks (`internal`), volumes (`workspace_data`, DB, Redis)
- Postgres and Redis instances, and therefore all circuit-breaker state
- `AGENTS_SHARED_DIR`, when each stack sets a distinct host path

**Genuinely shared, and the reason this document exists:**

| Resource                  | Shared? | Note                                                        |
| ------------------------- | ------- | ----------------------------------------------------------- |
| Ephemeral TCP port pool   | **Yes** | The one that caused the outage. Budgeted above.              |
| Published host ports      | **Yes** | Each stack must publish a distinct host port for `app`.      |
| Ollama on `11434`         | **Yes** | One host daemon serving every stack; its own churn source.   |
| Host CPU / memory         | Yes     | Bounded per stack by `deploy.resources.limits` in compose.   |
| File descriptors          | Yes     | Raise `ulimit -n` if running more than four stacks.          |

Checklist before adding a stack to a host:

- [ ] Distinct compose project name (`-p`)
- [ ] Distinct published host port for `app`
- [ ] Distinct `AGENTS_SHARED_DIR`
- [ ] `SDK_PROXY_MAX_CONCURRENCY` set so the host-wide sum still satisfies §3
- [ ] Host tuning LaunchDaemon installed (§2)
- [ ] Canary running in cron (§5)

---

## 7. Recovering from an exhausted host

If outbound networking is already dead:

```bash
# 1. Confirm it is port exhaustion, not the network.
curl -v https://api.anthropic.com 2>&1 | grep -i "assign requested address"
# "Immediate connect fail ... Can't assign requested address" in a few ms = exhaustion.

scripts/port-pressure-canary.sh

# 2. Find the stack responsible. lsof will show almost nothing — a TIME_WAIT
#    socket has no owning process. Attribute by destination instead.
netstat -an -p tcp | awk '$NF == "TIME_WAIT" {print $5}' \
  | sed 's/\.[0-9]*$//' | sort | uniq -c | sort -rn | head

# 3. Stop the offender's proxy and workers.
docker stop <stack>-sdk-proxy-1 <stack>-worker-agents-1

# 4. Widen the pool immediately (the LaunchDaemon makes this permanent).
sudo sysctl -w net.inet.ip.portrange.first=16384
sudo sysctl -w net.inet.tcp.msl=1000

# 5. Wait ~30s for TIME_WAIT to drain, then re-check.
scripts/port-pressure-canary.sh
```

Then fix the root cause — almost always an exhausted or revoked credential.
Top up at claude.ai/settings/usage or rotate the token, then either edit the
provider in the UI (which clears the circuit) or press **Retry now** on the
banner.

---

## 8. Known remaining churn sources

The incident's socket census showed two smaller sources beyond the Anthropic
loop, both now bounded but neither fully investigated:

- **1,496 dead sockets to Ollama on `11434`.** Ollama now goes through the
  same circuit breaker (`Providers::OllamaAdapter`), so a failing local model
  can no longer loop without bound. Ollama is one host daemon shared by every
  stack, though, so its own connection handling is still worth a look.
- **5,901 dead sockets to `127.0.0.1`.** Container-internal traffic (Redis,
  Postgres, the MCP tool bridge). Bounded by the per-stack concurrency ceiling
  in aggregate, but the per-connection lifetime has not been audited.

Neither was load-bearing for the outage. Revisit if the canary reports
sustained pressure with all circuits closed.
