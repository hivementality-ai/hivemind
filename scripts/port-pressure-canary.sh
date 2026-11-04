#!/usr/bin/env bash
#
# Host-level canary for ephemeral port pressure.
#
# On 2026-08-24 a Hivemind stack retried a permanently-failing provider call
# for 40 hours and drove TIME_WAIT to 20,775 sockets against a 16,384-port
# pool, killing outbound networking for every process on the Mac mini. This
# one number would have caught it on day one.
#
# Usage:
#   scripts/port-pressure-canary.sh                # one check, human output
#   scripts/port-pressure-canary.sh --json         # one check, JSON
#   scripts/port-pressure-canary.sh --watch 60     # loop every 60s
#
# Exit codes: 0 ok, 1 warning, 2 critical. Wire it into cron or a monitor.

set -euo pipefail

WARN_THRESHOLD="${PORT_CANARY_WARN:-8000}"
CRIT_THRESHOLD="${PORT_CANARY_CRIT:-14000}"
JSON=false
WATCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  JSON=true; shift ;;
    --watch) WATCH="${2:-60}"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

pool_size() {
  local first last
  first=$(sysctl -n net.inet.ip.portrange.first 2>/dev/null || echo 49152)
  last=$(sysctl -n net.inet.ip.portrange.last 2>/dev/null || echo 65535)
  echo $(( last - first + 1 ))
}

check() {
  local time_wait total pool pct level top
  time_wait=$(netstat -an -p tcp 2>/dev/null | awk '$NF == "TIME_WAIT"' | wc -l | tr -d ' ')
  total=$(netstat -an -p tcp 2>/dev/null | tail -n +3 | wc -l | tr -d ' ')
  pool=$(pool_size)
  pct=$(( time_wait * 100 / (pool > 0 ? pool : 1) ))

  if   (( time_wait >= CRIT_THRESHOLD )); then level=critical
  elif (( time_wait >= WARN_THRESHOLD )); then level=warning
  else level=ok
  fi

  # Where the churn points, so attribution does not need lsof (a TIME_WAIT
  # socket has no owning process — the kernel holds it after the process dies).
  top=$(netstat -an -p tcp 2>/dev/null | awk '$NF == "TIME_WAIT" {print $5}' \
        | sed 's/\.[0-9]*$//' | sort | uniq -c | sort -rn | head -5 \
        | awk '{printf "%s%s=%s", (NR>1 ? "," : ""), $2, $1}')

  if $JSON; then
    printf '{"level":"%s","time_wait":%s,"total_sockets":%s,"pool_size":%s,"pct_of_pool":%s,"top_remotes":"%s"}\n' \
      "$level" "$time_wait" "$total" "$pool" "$pct" "$top"
  else
    printf '[%s] %-8s TIME_WAIT=%s (%s%% of %s-port pool)  total_tcp=%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$time_wait" "$pct" "$pool" "$total"
    [[ -n "$top" ]] && printf '           top remotes: %s\n' "$top"
    if [[ "$level" != ok ]]; then
      printf '           A stack is churning connections. Check each sdk-proxy:\n'
      printf '             docker ps --format "{{.Names}}" | grep sdk-proxy | xargs -I{} sh -c "echo {}; docker exec {} wget -qO- http://localhost:3003/health"\n'
      printf '           A circuit reporting degraded=true names the credential at fault.\n'
    fi
  fi

  case "$level" in ok) return 0 ;; warning) return 1 ;; critical) return 2 ;; esac
}

if (( WATCH > 0 )); then
  while true; do check || true; sleep "$WATCH"; done
else
  check
fi
