#!/usr/bin/env bash
# ============================================================
# Hivemind 🐝 — Host ephemeral-port tuning
# ============================================================
# Installs (or repairs) the LaunchDaemon that widens the macOS ephemeral
# port pool and shortens TIME_WAIT, so the tuning survives a reboot.
#
# Why this is a host script and not a container:
#   On macOS, Docker Desktop runs the containers inside a Linux VM but
#   routes their egress through the *host's* socket pool via
#   com.docker.backend. So every stack on the box draws from one Darwin
#   port range, and no container can widen it — `net.inet.*` sysctls are
#   Darwin kernel state, unreachable from a Linux namespace. The only
#   vehicle that reaches the host is a script the operator runs, which is
#   why this hangs off scripts/upgrade.sh.
#
# This is headroom, NOT the fix. A stack retrying without bound exhausts
# 49k ports too; it just takes longer. See MULTI-STACK.md.
#
# Usage:
#   ./scripts/host-tuning.sh            # install/repair, prompting for sudo
#   ./scripts/host-tuning.sh --check    # report only; exit 1 if drifted
#   ./scripts/host-tuning.sh --quiet    # only speak up when something is wrong
# ============================================================

set -euo pipefail

HIVEMIND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$HIVEMIND_DIR/scripts/hivemind-host-tuning.plist"
# Overridable so the drift logic can be exercised without root.
PLIST_DST="${HIVEMIND_PLIST_DST:-/Library/LaunchDaemons/com.hivemind.host-tuning.plist}"
LABEL="com.hivemind.host-tuning"

# Must match the ProgramArguments in the plist. Checked, not assumed —
# a plist that says one thing while the kernel says another is the exact
# drift this script exists to catch.
declare -a WANT_KEYS=(net.inet.ip.portrange.first net.inet.tcp.msl)
declare -a WANT_VALS=(16384 1000)

CHECK_ONLY=false
QUIET=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --quiet) QUIET=true ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 64 ;;
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { $QUIET || echo -e "${CYAN}▸${NC} $*"; }
ok()   { $QUIET || echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }

# ----------------------------------------------------------
# Only macOS needs this
# ----------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  # On Linux, Docker networks are real namespaces with their own port
  # space; containers do not draw on the host's ephemeral range the way
  # Docker Desktop's userland proxy does. Nothing to tune here.
  ok "Not macOS — host port tuning does not apply."
  exit 0
fi

# ----------------------------------------------------------
# What is true right now
# ----------------------------------------------------------
sysctl_drift=false
for i in "${!WANT_KEYS[@]}"; do
  key="${WANT_KEYS[$i]}"
  want="${WANT_VALS[$i]}"
  have="$(sysctl -n "$key" 2>/dev/null || echo "?")"
  if [ "$have" != "$want" ]; then
    sysctl_drift=true
    warn "$key is $have, want $want"
  fi
done

daemon_missing=false
[ -f "$PLIST_DST" ] || daemon_missing=true

# An installed-but-stale plist is worse than a missing one: it looks
# handled and reverts to the wrong values on the next boot.
daemon_stale=false
if [ "$daemon_missing" = false ] && ! cmp -s "$PLIST_SRC" "$PLIST_DST"; then
  daemon_stale=true
fi

# Always report the range, never the size alone. A tuned host has a pool of
# 49,152 ports and an untuned one starts at port 49152, so that single number
# reads as success and as failure depending on which field you think it is.
# The endpoints are unambiguous.
describe_pool() {
  local first last
  first="$(sysctl -n net.inet.ip.portrange.first 2>/dev/null || echo 49152)"
  last="$(sysctl -n net.inet.ip.portrange.last 2>/dev/null || echo 65535)"
  echo "ports ${first}-${last} ($(( last - first + 1 )) available)"
}

timewait_now=$(( $(sysctl -n net.inet.tcp.msl 2>/dev/null || echo 15000) * 2 / 1000 ))
info "Ephemeral pool: $(describe_pool), TIME_WAIT ${timewait_now}s"

if [ "$sysctl_drift" = false ] && [ "$daemon_missing" = false ] && [ "$daemon_stale" = false ]; then
  ok "Host tuning is installed and live."
  exit 0
fi

$daemon_missing && warn "LaunchDaemon not installed: $PLIST_DST"
$daemon_stale   && warn "LaunchDaemon is stale (differs from $PLIST_SRC)"

if [ "$CHECK_ONLY" = true ]; then
  echo ""
  fail "Host tuning has drifted. Fix it with: ./scripts/host-tuning.sh"
  exit 1
fi

# ----------------------------------------------------------
# Apply
# ----------------------------------------------------------
if [ ! -f "$PLIST_SRC" ]; then
  fail "Missing $PLIST_SRC — cannot install."
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    fail "Need root to install $PLIST_DST, and sudo is not available."
    exit 1
  fi
  SUDO="sudo"
  if ! sudo -n true 2>/dev/null; then
    echo ""
    info "Installing the host tuning needs administrator rights."
    info "You will be asked for your password once."
    echo ""
  fi
fi

info "Installing $PLIST_DST"
$SUDO cp "$PLIST_SRC" "$PLIST_DST"
$SUDO chown root:wheel "$PLIST_DST"
$SUDO chmod 644 "$PLIST_DST"

# bootout first so a stale definition is genuinely replaced rather than
# left loaded. Both calls are allowed to fail: not-loaded is not an error.
$SUDO launchctl bootout "system/$LABEL" 2>/dev/null || true
if ! $SUDO launchctl bootstrap system "$PLIST_DST" 2>/dev/null; then
  # Older macOS predates `bootstrap`.
  $SUDO launchctl load -w "$PLIST_DST" 2>/dev/null || true
fi

# RunAtLoad fires the sysctls, but do not take that on faith — apply them
# directly too, so this run leaves the kernel correct even if launchd
# deferred the job.
$SUDO sysctl -w net.inet.ip.portrange.first=16384 >/dev/null
$SUDO sysctl -w net.inet.ip.portrange.hifirst=16384 >/dev/null
$SUDO sysctl -w net.inet.tcp.msl=1000 >/dev/null

# ----------------------------------------------------------
# Verify what we actually achieved
# ----------------------------------------------------------
verify_failed=false
for i in "${!WANT_KEYS[@]}"; do
  key="${WANT_KEYS[$i]}"
  want="${WANT_VALS[$i]}"
  have="$(sysctl -n "$key" 2>/dev/null || echo "?")"
  [ "$have" = "$want" ] || { fail "$key is $have after apply, wanted $want"; verify_failed=true; }
done
[ -f "$PLIST_DST" ] || { fail "$PLIST_DST still missing after install"; verify_failed=true; }

if [ "$verify_failed" = true ]; then
  exit 1
fi

ok "Host tuning installed and live: $(describe_pool), TIME_WAIT 2s, survives reboot."
