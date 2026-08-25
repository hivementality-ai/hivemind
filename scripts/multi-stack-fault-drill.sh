#!/usr/bin/env bash
#
# Multi-stack fault drill — replays the 2026-08-24 outage against live
# containers and asserts it stays local.
#
# Unit and integration coverage for the same guarantees lives in
# sdk-proxy/__tests__/guard.test.js and
# spec/services/providers/resource_discipline_spec.rb. This drill exists
# because those cannot prove the part that actually broke: that a runaway in
# one *container* does not consume the *host's* ephemeral port pool. That
# needs real Docker, real sockets, and a real host, so it is an operator
# drill rather than a CI job.
#
# What it does:
#   1. Records baseline host TIME_WAIT.
#   2. Points the faulty stack's sdk-proxy at a credential that always fails
#      permanently, and drives it hard for the drill window.
#   3. Asserts: attempts are bounded, its circuit opens, TIME_WAIT stays under
#      the ceiling, the healthy stack keeps serving, and the host can still
#      open outbound sockets.
#
# Usage:
#   scripts/multi-stack-fault-drill.sh <faulty-stack> <healthy-stack> [seconds]
#
# Example:
#   scripts/multi-stack-fault-drill.sh hivemind-parents hivemind 600

set -uo pipefail

FAULTY="${1:-}"
HEALTHY="${2:-}"
DURATION="${3:-600}"
TIME_WAIT_CEILING="${TIME_WAIT_CEILING:-2000}"
CONCURRENCY="${DRILL_CONCURRENCY:-20}"

if [[ -z "$FAULTY" || -z "$HEALTHY" ]]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

FAULTY_PROXY="${FAULTY}-sdk-proxy-1"
HEALTHY_PROXY="${HEALTHY}-sdk-proxy-1"
FAIL=0

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }

time_wait() { netstat -an -p tcp 2>/dev/null | awk '$NF == "TIME_WAIT"' | wc -l | tr -d ' '; }
proxy_health() { docker exec "$1" wget -qO- http://localhost:3003/health 2>/dev/null; }
jqf() { /usr/bin/env node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(eval('('+d+')')$1)}catch(e){console.log('')}})"; }

say "Preflight"
for c in "$FAULTY_PROXY" "$HEALTHY_PROXY"; do
  docker inspect "$c" >/dev/null 2>&1 || { fail "container not found: $c"; exit 1; }
done
pass "both stacks are up"

BASELINE=$(time_wait)
printf '  baseline TIME_WAIT=%s  ceiling=%s\n' "$BASELINE" "$TIME_WAIT_CEILING"

say "Driving the faulty stack for ${DURATION}s at concurrency ${CONCURRENCY}"
# A syntactically valid but permanently-invalid credential: the provider
# answers 401, which the classifier must treat as permanent.
BAD_TOKEN="sk-ant-api03-drill-invalid-credential"
DEADLINE=$(( $(date +%s) + DURATION ))
REQUESTS=0

drive() {
  while [[ $(date +%s) -lt $DEADLINE ]]; do
    docker exec "$FAULTY_PROXY" wget -q -O /dev/null \
      --header="Content-Type: application/json" \
      --header="Authorization: Bearer ${BAD_TOKEN}" \
      --post-data='{"messages":[{"role":"user","content":"drill"}],"max_tokens":16}' \
      http://localhost:3003/v1/chat 2>/dev/null
  done
}

for _ in $(seq "$CONCURRENCY"); do drive & done

PEAK=0
while [[ $(date +%s) -lt $DEADLINE ]]; do
  current=$(time_wait)
  (( current > PEAK )) && PEAK=$current
  printf '\r  TIME_WAIT=%-8s peak=%-8s %ss left   ' \
    "$current" "$PEAK" "$(( DEADLINE - $(date +%s) ))"
  sleep 5
done
wait 2>/dev/null
printf '\n'

say "Assertions"

# 1. Host resource discipline — the assertion the incident failed.
if (( PEAK < TIME_WAIT_CEILING )); then
  pass "host TIME_WAIT peaked at $PEAK, under the $TIME_WAIT_CEILING ceiling"
else
  fail "host TIME_WAIT peaked at $PEAK, at or over the $TIME_WAIT_CEILING ceiling"
fi

# 2. The faulty stack degraded loudly and stopped dialling.
FAULTY_HEALTH=$(proxy_health "$FAULTY_PROXY")
if [[ "$(echo "$FAULTY_HEALTH" | jqf '.degraded')" == "true" ]]; then
  pass "faulty stack reports degraded: $(echo "$FAULTY_HEALTH" | jqf '.reason')"
else
  fail "faulty stack did not report degraded — the outage would be silent again"
fi

ACQUIRED=$(echo "$FAULTY_HEALTH" | jqf '.concurrency.total_acquired')
if [[ -n "$ACQUIRED" ]] && (( ACQUIRED < 100 )); then
  pass "attempts that reached the network: $ACQUIRED (bounded and countable)"
else
  fail "attempts reached the network: ${ACQUIRED:-unknown} — expected a small bounded number"
fi

SHED=$(echo "$FAULTY_HEALTH" | jqf '.concurrency.total_shed')
printf '  (requests shed rather than spawned: %s)\n' "${SHED:-0}"

# 3. The sibling stack was unaffected.
HEALTHY_HEALTH=$(proxy_health "$HEALTHY_PROXY")
if [[ -n "$HEALTHY_HEALTH" && "$(echo "$HEALTHY_HEALTH" | jqf '.degraded')" == "false" ]]; then
  pass "healthy stack kept serving throughout"
else
  fail "healthy stack was affected: ${HEALTHY_HEALTH:-unreachable}"
fi

# 4. The host can still open outbound sockets — the thing that actually broke.
if curl -s -o /dev/null --max-time 10 https://api.anthropic.com 2>/dev/null \
   || [[ $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://api.anthropic.com) != "000" ]]; then
  pass "host outbound networking intact"
else
  fail "host cannot open outbound sockets — port pool exhausted"
fi

say "Recovery"
docker exec "$FAULTY_PROXY" wget -q -O /dev/null --post-data='{}' \
  --header="Content-Type: application/json" \
  --header="X-Internal-Secret: ${INTERNAL_API_SECRET:-}" \
  http://localhost:3003/admin/circuit/reset 2>/dev/null
if [[ "$(proxy_health "$FAULTY_PROXY" | jqf '.degraded')" == "false" ]]; then
  pass "circuit cleared; the stack is serving again"
else
  fail "circuit did not clear"
fi

say "Result"
if (( FAIL == 0 )); then
  printf '  \033[32mDrill passed.\033[0m One stack lost provider access; it degraded\n'
  printf '  locally and loudly, and nothing else on the host noticed.\n'
else
  printf '  \033[31mDrill failed.\033[0m See MULTI-STACK.md §4 for the four bounds\n'
  printf '  that are supposed to stop this, and check which one did not hold.\n'
fi
exit $FAIL
