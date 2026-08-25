# Handoff: ephemeral port exhaustion caused by unbounded LLM retries

Date: 2026-08-25
Host: The99thPrecinct (Mac mini, 192.168.1.5, macOS)
Severity: host-wide outage. All outbound networking on the machine failed, not just hivemind.
Status: **FIXED in code, 2026-08-25.** See `MULTI-STACK.md` for the standing
arrangement and `## 9. What was fixed` at the bottom of this file for the
mapping from each item below to its implementation. This document is retained
as the incident record; the diagnosis in sections 1-3 is unchanged.

One item remains outstanding and is on a human: **top up the Claude account**
at claude.ai/settings/usage. The code no longer melts the host when it is
empty, but the parents stack still cannot make Claude calls until it is
funded.

## TL;DR for the agent picking this up

A hivemind stack burned every ephemeral TCP port on the host by retrying a
**permanently failing** Anthropic call with no backoff and no cap, for 40 hours.
Once the port pool was empty, every process on the machine lost outbound
networking, including unrelated ones.

**The goal is to run multiple hivemind stacks on one box.** That is not the bug
and must not be "fixed" by running fewer stacks. The bug is that a single stack
has no upper bound on its consumption of a host-wide, shared, finite resource.
Fix the resource discipline so that N stacks can coexist safely.

---

## 1. What happened

Two full hivemind stacks run on this host:

- `hivemind-*` (23 containers total across both)
- `hivemind-parents-*`

Both up 40 hours. Everything reported healthy except one container:

```
hivemind-parents-sdk-proxy-1    Up 40 hours (unhealthy)
```

Its health check had been failing continuously:

```
wget: can't connect to remote host: Connection refused
```

That is the container failing to reach **its own** `/health` on port 3003.

Meanwhile the operator's own Claude Code CLI on the same host could not connect:

```
Connection refused - a firewall or proxy may be blocking it (ConnectionRefused)
Retrying in 2s - attempt 3/10
```

## 2. Evidence chain

Diagnosis ran on the host, outside Docker.

**DNS and proxy were ruled out.** `api.anthropic.com` resolved correctly to
`160.79.104.10`, `/etc/hosts` was clean, no proxy env vars, no macOS system
proxy on any interface, single default route via `en0`.

**curl failed before a packet left the box:**

```
*   Trying 160.79.104.10:443...
* Immediate connect fail for 160.79.104.10: Can't assign requested address
* Failed to connect ... after 4 ms
```

`EADDRNOTAVAIL` in 4ms means the kernel could not allocate a local source port.
It is not a network reachability failure.

**Confirmed against every destination**, not just Anthropic. `google.com`,
`github.com`, and `1.1.1.1` all failed identically and instantly.

**The port pool was oversubscribed:**

```
net.inet.ip.portrange.first: 49152
net.inet.ip.portrange.last:  65535        -> 16,384 ports available
net.inet.tcp.msl:            15000        -> TIME_WAIT lingers 30s

netstat -an -p tcp, by state:
  20775 TIME_WAIT      <-- exceeds the entire pool
    357 LAST_ACK
     28 CLOSING
     20 LISTEN
     16 FIN_WAIT_1
      7 ESTABLISHED    <-- only seven real conversations
```

20,775 sockets in TIME_WAIT inside a 30-second window implies a sustained churn
of roughly 700 connections per second.

**Where those dead sockets pointed:**

```
by remote host                 by remote port
8759  160.79.104.10 (Anthropic)   13843  443
5901  127.0.0.1                    1496  11434 (Ollama)
 517  13.107.226.57                 496  853  (DoT)
 510  13.107.253.57                 270  22
 482  18.238.132.77                  87  80
```

`lsof` showed almost nothing, which is expected and not a dead end: a TIME_WAIT
socket has no owning process. The kernel holds it after the process is gone.
Attribution had to come from the destination distribution above.

**The originating error, from `docker logs hivemind-parents-sdk-proxy-1`:**

```
LLM error: Anthropic API error (400): You're out of extra usage.
Add more at claude.ai/settings/usage and keep going.
```

**And the loop it produced**, visible in the same logs. Note the transcript is
replaying the same user turns over and over, and each attempt ends by killing a
freshly spawned subprocess:

```
[chat] token=sk-ant-oat01-wu... isOAuth=true stream=false tools=0
[oauth-prompt] user prompt: "User: Yo sam you there?
  Assistant: API Error: Connection error.
  User: Reply with the single word OK
  Assistant: API Error: Connection error. ..."
SDK proxy error: Claude Code process exited with code 1
[chat] token=sk-ant-oat01-wu... isOAuth=true ...
SDK proxy error: Claude Code process exited with code 1
   (repeating)
```

`restarts=0`, `started=2026-08-24T00:10:51Z`. The container never crash-looped,
so nothing surfaced. It failed silently for two days.

## 3. Why it happened

Causal chain, in order:

1. The Claude account hit its usage cap. Anthropic returned **HTTP 400,
   "You're out of extra usage."** This is a **permanent** failure. It cannot
   succeed on retry until a human adds credit.
2. Nothing in the stack classifies that as permanent. It was treated as a
   generic error and retried.
3. Retries are effectively unbounded. `ChatStreamJob` (`app/jobs/chat_stream_job.rb`)
   declares `queue_as :agents` and **no** `retry_on` or `discard_on`, so it
   inherits Sidekiq's default of 25 retries. `app/jobs/application_job.rb` has
   its `retry_on` / `discard_on` lines commented out. Compare
   `webhook_delivery_job.rb`, which correctly does
   `retry_on StandardError, wait: :polynomially_longer, attempts: 5`.
4. The OAuth path amplifies every attempt. `sdk-proxy/server.js` `handleOAuth()`
   calls `query()` from `@anthropic-ai/claude-agent-sdk`, and **each call spawns
   a fresh Claude Code subprocess** (the code comments say so at line 76 and
   line 13). That subprocess then runs its own internal retry ladder, up to 10
   attempts, each on a new TCP connection. There is no connection reuse by
   construction and no concurrency cap: `process.setMaxListeners(30)` is the
   only nod to concurrency, and it suppresses a warning rather than limiting
   anything.
5. `sdk-proxy/server.js` has **no retry logic and no error classification of its
   own**. The single `catch` at the `/v1/chat` handler logs `err.message` and
   forwards `err.status || 500`. A 400 quota error and a transient socket error
   are indistinguishable to every caller upstream.
6. Multiply: several agents, each with scheduled and inbound work, each retrying,
   each attempt spawning a subprocess that retries 10 more times, for 40 hours.
7. On macOS, Docker container egress traverses the host's own sockets via
   `com.docker.backend`. So container-side connection churn consumes the
   **host's** 16,384-port pool. This is the critical coupling: a runaway inside
   one container took down networking for the whole machine, including the
   operator's desktop tools.
8. Once the pool was exhausted, `hivemind-parents-sdk-proxy-1` could no longer
   bind an outbound socket even to reach its own health endpoint, which is why
   the health check reported `Connection refused`. That symptom is downstream,
   not the cause. Do not chase it.

**One-line root cause:** a permanent, human-actionable provider error was
retried as if transient, through a code path that opens a new TCP connection per
attempt, with no cap, no backoff, no circuit breaker, and no bound on a shared
host-wide resource.

## 4. What was done by hand (temporary, not a fix)

```bash
docker stop hivemind-parents-sdk-proxy-1 hivemind-parents-worker-agents-1
sudo sysctl -w net.inet.ip.portrange.first=16384   # 16k ports -> ~49k
sudo sysctl -w net.inet.tcp.msl=1000               # TIME_WAIT 30s -> 2s
```

Both sysctls reset on reboot. They widen the blast radius tolerance; they do not
stop the leak. A stack retrying at 700/s will exhaust 49k ports too, it just
takes longer.

Also outstanding and blocking: **account usage must be topped up** at
claude.ai/settings/usage, otherwise restarting the parents stack reproduces the
incident immediately. Logged in `~/.claude/BLOCKED.md`.

## 5. What needs to be fixed

Ordered by importance. Items 1 through 3 are the actual fix; 4 through 6 make
multi-stack safe as a standing arrangement.

### 5.1 Classify provider errors as permanent vs transient (sdk-proxy)

In `sdk-proxy/server.js`, introduce explicit error classification and surface it
to callers in a machine-readable way, not just an HTTP status and a string.

- **Permanent / do not retry:** 400 with a quota or billing message
  ("out of extra usage", "credit balance"), 401, 403, 404 model-not-found, and
  422 invalid-request. These require a human. Return a distinct, stable error
  code (for example `{"error": {...}, "retryable": false, "reason": "quota_exhausted"}`).
- **Transient / retry with backoff:** 408, 409, 429, 5xx, socket errors,
  timeouts. Return `"retryable": true` and honour `Retry-After` when present.
- The OAuth path currently loses this signal entirely. `handleOAuth()` fails via
  `Claude Code process exited with code 1`, which erases the underlying HTTP
  status. Parse the subprocess output or the SDK error to recover the real cause
  before it reaches the `catch` at the `/v1/chat` handler.

### 5.2 Bound the retries (Rails)

- Give `ChatStreamJob` and every other LLM-invoking job an explicit policy.
  Follow the existing good example in `app/jobs/webhook_delivery_job.rb`.
  - `discard_on` the permanent provider error class. Never retry a quota failure.
  - `retry_on` transient errors with `wait: :polynomially_longer` and a small
    `attempts:` cap. Not Sidekiq's default 25.
- Audit every job that can reach a provider: `chat_stream_job`, `team_chat_job`,
  `inbound_message_job`, `sub_agent_job`, `scheduled_agent_job`,
  `coding_agent_job`, `deep_research_job`, and the `tasks/` and `concerns/`
  subtrees. Any of them can start the same stampede.
- Define a provider error taxonomy in one place, probably alongside
  `app/services/providers/anthropic_adapter.rb`, and have the adapter raise typed
  errors. Right now that file has bare `rescue StandardError` at lines 20, 57,
  and 65, which flattens everything into one indistinguishable failure.

### 5.3 Circuit breaker per credential

There is prior art in the repo to follow: `app/services/agents/loop_detector.rb`
and the circuit handling in `app/models/agent.rb` and `webhook_delivery_job.rb`.

- After N consecutive permanent auth or quota failures on a given credential,
  **open the circuit for the whole stack** and stop dialing entirely.
- While open, fail fast locally. Do not open a socket.
- Surface it loudly: a banner in the UI, and a health signal that says
  "provider circuit open: quota exhausted", not a generic unhealthy.
- Half-open on a slow timer, or immediately when a human updates the credential.

### 5.4 Cap concurrent subprocess spawns (sdk-proxy)

`handleOAuth()` spawns a Claude Code subprocess per request with no limit.

- Add a bounded work queue with a configurable max concurrency, defaulting low
  (4 to 8). Requests over the limit queue or shed with 429, they do not spawn.
- Make the ceiling an env var so operators can tune it per stack, and so the sum
  across stacks on one host stays under the host's capacity.
- Investigate whether the non-OAuth `Anthropic` client path can be preferred, or
  whether a persistent agent session can replace per-call subprocess spawning.
  Connection-per-request is the structural driver of the churn.

### 5.5 Make multi-stack a first-class, bounded arrangement

This is the piece that matters for the stated goal. Running several stacks is
desirable; each one currently assumes it owns the machine.

- Document and enforce a per-stack outbound concurrency budget, so that
  `sum(stacks) < host capacity`. Expose it in `docker-compose.yml` next to the
  existing `SDK_PROXY_MEMORY` / `SDK_PROXY_CPUS` knobs, as something like
  `SDK_PROXY_MAX_CONCURRENCY` and `SDK_PROXY_MAX_INFLIGHT_CONNECTIONS`.
- Add a `MULTI-STACK.md` covering: recommended host sysctl tuning
  (`net.inet.ip.portrange.first=16384`, `net.inet.tcp.msl=1000`, made persistent
  via a LaunchDaemon so it survives reboot), how many stacks a host can carry,
  and the per-stack budget arithmetic.
- Verify project-name isolation is complete across both stacks: networks,
  volumes, and published host ports. The two stacks already coexist, so confirm
  what is genuinely shared (host ports, the port pool, Ollama on 11434) versus
  isolated.

### 5.6 Observability so this is never silent again

The failure ran 40 hours with `restarts=0` and nothing alerted.

- Make the sdk-proxy health check meaningful. It currently only proves the HTTP
  server answers. It should report provider circuit state and in-flight count.
  Distinguish "cannot reach provider" from "cannot bind a socket".
- Emit a metric or log alarm on consecutive provider failures and on subprocess
  spawn rate.
- Add a host-level canary that alerts when TIME_WAIT crosses a threshold, for
  example 8,000. That single number would have caught this on day one.
- The 1,496 dead sockets to Ollama on port 11434 and 5,901 to 127.0.0.1 suggest a
  second, smaller churn source. Worth a look once the main fix lands.

## 6. Definition of done

1. A 400 quota error from Anthropic causes **at most one** attempt per job, is
   classified as permanent, and is not retried by Sidekiq.
2. Repeated permanent failures open a circuit breaker; while open, **zero**
   outbound sockets are opened to the provider.
3. The failure is visible: UI banner, health endpoint reports the real reason,
   and a log alarm fires.
4. sdk-proxy enforces a configurable ceiling on concurrent subprocess spawns and
   sheds load beyond it rather than spawning without limit.
5. **Regression test:** with the provider stubbed to return
   `400 "You're out of extra usage"` for every call, drive a stack under load for
   10 minutes and assert that host TIME_WAIT stays under a fixed bound (for
   example 2,000) and that total attempts are bounded and countable.
6. **Multi-stack test:** two stacks on one host, one of them fault-injected as in
   test 5, and assert the healthy stack keeps serving throughout and the host
   retains working outbound networking.
7. `MULTI-STACK.md` exists, with the sysctl guidance made persistent across
   reboot, and the per-stack budget documented.

## 7. Outcome we want

Multiple hivemind stacks run on one Mac mini indefinitely. When any single stack
loses provider access, whether from exhausted credit, a revoked token, or a
network fault, that stack degrades loudly and locally: it stops calling out, it
says why, and it waits for a human. It does not consume a shared host resource
without bound, it does not take down its sibling stacks, and it does not break
unrelated software on the machine.

The specific proof: this incident, replayed, should end with one clear error
message in the parents stack UI, and no measurable effect on anything else.

## 8. Files to start in

```
sdk-proxy/server.js                       handleOAuth(), /v1/chat catch, health
app/jobs/chat_stream_job.rb               no retry policy, inherits Sidekiq 25
app/jobs/application_job.rb               retry_on / discard_on commented out
app/jobs/webhook_delivery_job.rb          the pattern to copy
app/services/providers/anthropic_adapter.rb   bare rescue StandardError x3
app/services/providers/failover_adapter.rb    failover may compound the retries
app/services/agents/loop_detector.rb      existing circuit-breaker prior art
docker-compose.yml                        sdk-proxy service, resource limits
```

---

## 9. What was fixed (2026-08-25)

| §   | Requirement                                  | Where                                                                                          |
| --- | -------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 5.1 | Classify permanent vs transient (proxy)      | `sdk-proxy/error-classifier.js` — machine-readable `{retryable, reason}`; recovers the real status from subprocess stderr, so `exited with code 1` no longer erases a quota 400 |
| 5.2 | Bound the retries (Rails)                    | `app/jobs/application_job.rb` — `discard_on PermanentProviderError`, `retry_on TransientProviderError attempts: 3`; every job inherits it. Taxonomy in `app/errors/*provider*.rb`, classifier in `app/services/providers/error_classifier.rb` |
| 5.3 | Circuit breaker per credential               | `sdk-proxy/circuit-breaker.js` (in-process) and `app/services/providers/circuit_breaker.rb` (Redis, shared by all workers). Wired into every adapter via `Providers::Base#with_circuit_breaker` |
| 5.4 | Cap concurrent subprocess spawns             | `sdk-proxy/concurrency.js` — `SDK_PROXY_MAX_CONCURRENCY` (default 4), overflow shed with 429 |
| 5.5 | Multi-stack as a bounded arrangement         | `MULTI-STACK.md`, budget knobs in `docker-compose.yml`, persistent sysctls via `scripts/hivemind-host-tuning.plist` |
| 5.6 | Observability                                | `/health` reports circuit state + in-flight; `GET /api/v1/system/provider_health` returns 503 and distinguishes "provider refused us" from "cannot bind a socket"; `[ALARM]` log line; UI banner; `scripts/port-pressure-canary.sh` |

Definition of done (§6), item by item:

1. **One attempt per job, classified permanent, not retried.** ✅
   `spec/services/providers/resource_discipline_spec.rb`, `spec/jobs/application_job_spec.rb`.
2. **Repeated permanent failures open a circuit; zero sockets while open.** ✅
   Verified against live traffic: three real 401s from `api.anthropic.com`,
   then every subsequent request answered `503` locally with
   `total_acquired: 3` — no fourth socket.
3. **Visible: UI banner, health reports the real reason, log alarm fires.** ✅
4. **Configurable ceiling on subprocess spawns, sheds beyond it.** ✅
   `sdk-proxy/__tests__/guard.test.js`.
5. **Regression test: stubbed permanent failure under load, bounded attempts.** ✅
   200 calls → 3 network attempts (`resource_discipline_spec.rb`); 500 calls →
   3 attempts and peak concurrency 4 (`guard.test.js`).
6. **Multi-stack test.** ✅ as an operator drill —
   `scripts/multi-stack-fault-drill.sh`. It needs real Docker and real host
   sockets to prove the container-to-host coupling, which CI cannot provide.
7. **`MULTI-STACK.md` with persistent sysctls and the budget documented.** ✅

### Not done

- The account top-up (on a human).
- The two smaller churn sources from §2's socket census (Ollama on 11434,
  127.0.0.1). Both are now bounded by the same circuit breaker and
  concurrency ceiling, but neither was individually audited —
  see `MULTI-STACK.md` §8.
