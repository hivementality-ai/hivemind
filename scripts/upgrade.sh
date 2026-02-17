#!/usr/bin/env bash
# ============================================================
# Hivemind 🐝 — Upgrade Script
# ============================================================
# Usage:
#   ./scripts/upgrade.sh              # upgrade to latest
#   ./scripts/upgrade.sh v2026.02.3   # upgrade to specific version
# ============================================================

set -euo pipefail

HIVEMIND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_VERSION="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
fail()  { echo -e "${RED}✗${NC} $*"; exit 1; }

header() {
  echo ""
  echo -e "${BOLD}${YELLOW}🐝 Hivemind Upgrade${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ----------------------------------------------------------
# Pre-flight checks
# ----------------------------------------------------------
preflight() {
  cd "$HIVEMIND_DIR"

  # Verify we're in a Hivemind directory
  if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yaml" ]; then
    fail "Not a Hivemind directory: $HIVEMIND_DIR"
  fi

  # Check Docker is running
  if ! docker info &>/dev/null 2>&1; then
    fail "Docker is not running. Start Docker and try again."
  fi

  # Check git
  if ! command -v git &>/dev/null; then
    fail "git is required."
  fi

  # Current version
  CURRENT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 'unknown')"
  ok "Current version: ${BOLD}$CURRENT_VERSION${NC}"
}

# ----------------------------------------------------------
# Fetch latest version info
# ----------------------------------------------------------
fetch_latest() {
  if [ -n "$TARGET_VERSION" ]; then
    LATEST_VERSION="${TARGET_VERSION#v}"
    ok "Target version: ${BOLD}$LATEST_VERSION${NC}"
    return
  fi

  info "Checking for updates..."
  git fetch --tags --quiet 2>/dev/null

  LATEST_VERSION="$(git tag -l 'v*' --sort=-version:refname | head -1 | sed 's/^v//' || echo '')"

  if [ -z "$LATEST_VERSION" ]; then
    # Fall back to GitHub API
    LATEST_VERSION="$(curl -sf https://api.github.com/repos/hivementality-ai/hivemind/releases/latest 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/' || echo '')"
  fi

  if [ -z "$LATEST_VERSION" ]; then
    fail "Could not determine latest version. Try: ./scripts/upgrade.sh v2026.02.1"
  fi

  ok "Latest version: ${BOLD}$LATEST_VERSION${NC}"
}

# ----------------------------------------------------------
# Compare versions
# ----------------------------------------------------------
check_version() {
  if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    ok "Already on the latest version ($CURRENT_VERSION). Nothing to do."
    exit 0
  fi

  echo ""
  info "Upgrade: ${BOLD}$CURRENT_VERSION${NC} → ${BOLD}$LATEST_VERSION${NC}"
}

# ----------------------------------------------------------
# Check for breaking changes
# ----------------------------------------------------------
check_breaking() {
  local release_body
  release_body="$(curl -sf "https://api.github.com/repos/hivementality-ai/hivemind/releases/tags/v$LATEST_VERSION" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('body',''))" 2>/dev/null || echo '')"

  if echo "$release_body" | grep -qi "breaking\|⚠️"; then
    echo ""
    warn "This release contains ${BOLD}BREAKING CHANGES${NC}:"
    echo "$release_body" | grep -i "breaking\|⚠️" | head -5
    echo ""
    read -p "Continue with upgrade? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      info "Upgrade cancelled."
      exit 0
    fi
  fi
}

# ----------------------------------------------------------
# Backup database
# ----------------------------------------------------------
backup_database() {
  local backup_dir="$HIVEMIND_DIR/backups"
  mkdir -p "$backup_dir"

  local backup_file="$backup_dir/pre-upgrade-$(date +%Y%m%d-%H%M%S).sql"

  info "Backing up database..."

  # Find the postgres container name
  local pg_container
  pg_container="$(docker compose ps --format '{{.Name}}' 2>/dev/null | grep -i postgres | head -1 || echo '')"

  if [ -z "$pg_container" ]; then
    warn "No running postgres container found. Skipping backup."
    return
  fi

  if docker exec "$pg_container" pg_dump -U hivemind hivemind_production > "$backup_file" 2>/dev/null; then
    ok "Database backed up: $backup_file"
  else
    # Try alternative database name
    if docker exec "$pg_container" pg_dump -U hivemind hivemind_development > "$backup_file" 2>/dev/null; then
      ok "Database backed up: $backup_file"
    else
      warn "Database backup failed. Continuing anyway..."
    fi
  fi

  # Keep last 5 backups
  local count
  count="$(find "$backup_dir" -name "pre-upgrade-*.sql" | wc -l | tr -d ' ')"
  if [ "$count" -gt 5 ]; then
    find "$backup_dir" -name "pre-upgrade-*.sql" | sort | head -n -5 | xargs rm -f
    info "Cleaned old backups (kept last 5)"
  fi
}

# ----------------------------------------------------------
# Pull and build
# ----------------------------------------------------------
pull_and_build() {
  cd "$HIVEMIND_DIR"

  info "Pulling latest code..."
  if [ -n "$TARGET_VERSION" ]; then
    git fetch --tags --quiet
    git checkout "v$LATEST_VERSION" 2>/dev/null || git checkout "$TARGET_VERSION"
  else
    git checkout main 2>/dev/null || true
    git pull origin main --quiet
  fi

  info "Building containers (version: $LATEST_VERSION)..."
  HIVEMIND_VERSION="$LATEST_VERSION" docker compose build --build-arg HIVEMIND_VERSION="$LATEST_VERSION" --quiet
  ok "Build complete"
}

# ----------------------------------------------------------
# Restart services
# ----------------------------------------------------------
restart_services() {
  info "Restarting Hivemind..."
  HIVEMIND_VERSION="$LATEST_VERSION" docker compose up -d

  # Wait for health
  echo -n "Waiting for Hivemind to be ready..."
  local attempts=0
  while ! curl -sf http://localhost:3001/up &>/dev/null; do
    sleep 3
    echo -n "."
    attempts=$((attempts + 1))
    if [ $attempts -gt 40 ]; then
      echo ""
      warn "Taking longer than expected. Check: docker compose logs rails"
      return
    fi
  done
  echo ""
  ok "Hivemind is running!"
}

# ----------------------------------------------------------
# Verify
# ----------------------------------------------------------
verify() {
  local api_version
  api_version="$(curl -sf http://localhost:3001/api/v1/system/version 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('current','unknown'))" 2>/dev/null || echo 'unknown')"

  if [ "$api_version" = "$LATEST_VERSION" ]; then
    ok "Version verified: $api_version"
  else
    warn "Version API reports: $api_version (expected: $LATEST_VERSION)"
    info "This may be normal if the version tag hasn't been set yet."
  fi
}

# ----------------------------------------------------------
# Done
# ----------------------------------------------------------
print_success() {
  echo ""
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${GREEN}🐝 Upgrade complete!${NC}"
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BOLD}Version:${NC}   $CURRENT_VERSION → $LATEST_VERSION"
  echo -e "  ${BOLD}Open:${NC}      http://localhost:3001"
  echo -e "  ${BOLD}Logs:${NC}      docker compose logs -f"
  echo -e "  ${BOLD}Changelog:${NC} https://github.com/hivementality-ai/hivemind/releases/tag/v$LATEST_VERSION"
  echo ""
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------
main() {
  header
  preflight
  fetch_latest
  check_version
  check_breaking
  backup_database
  pull_and_build
  restart_services
  verify
  print_success
}

main "$@"
