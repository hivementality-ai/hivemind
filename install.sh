#!/usr/bin/env bash
# ============================================================
# Hivemind 🐝 — One-Line Installer
# ============================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/your-org/hivemind/main/install.sh | bash
#   — or —
#   git clone ... && cd hivemind && ./install.sh
# ============================================================

set -euo pipefail

HIVEMIND_DIR="${HIVEMIND_DIR:-$HOME/hivemind}"
REPO_URL="${HIVEMIND_REPO:-https://github.com/your-org/hivemind.git}"
BRANCH="${HIVEMIND_BRANCH:-main}"

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
  echo -e "${BOLD}${YELLOW}🐝 Hivemind Installer${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ----------------------------------------------------------
# Detect OS
# ----------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="mac" ;;
    *)       fail "Unsupported OS: $(uname -s). Hivemind supports macOS and Linux." ;;
  esac
  ARCH="$(uname -m)"
  ok "Detected: $OS ($ARCH)"
}

# ----------------------------------------------------------
# Install Docker if missing
# ----------------------------------------------------------
install_docker() {
  if command -v docker &>/dev/null; then
    ok "Docker already installed: $(docker --version)"
    return
  fi

  info "Installing Docker..."

  if [ "$OS" = "mac" ]; then
    # macOS — try Homebrew first, then direct download
    if command -v brew &>/dev/null; then
      info "Installing Docker Desktop via Homebrew..."
      brew install --cask docker
    else
      echo ""
      echo -e "${YELLOW}Docker Desktop is required on macOS.${NC}"
      echo "Install it from: https://docs.docker.com/desktop/install/mac-install/"
      echo ""
      echo "After installing, open Docker Desktop and wait for it to start,"
      echo "then re-run this script."
      exit 1
    fi

    # Wait for Docker Desktop to be ready
    if ! docker info &>/dev/null 2>&1; then
      info "Starting Docker Desktop..."
      open -a Docker
      echo -n "Waiting for Docker to start..."
      local attempts=0
      while ! docker info &>/dev/null 2>&1; do
        sleep 2
        echo -n "."
        attempts=$((attempts + 1))
        if [ $attempts -gt 60 ]; then
          echo ""
          fail "Docker didn't start in time. Open Docker Desktop manually, then re-run."
        fi
      done
      echo ""
    fi
  else
    # Linux — official install script
    info "Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | sh

    # Add current user to docker group
    if ! groups | grep -q docker; then
      sudo usermod -aG docker "$USER"
      warn "Added $USER to docker group. You may need to log out and back in."
    fi

    # Start and enable Docker
    sudo systemctl start docker 2>/dev/null || true
    sudo systemctl enable docker 2>/dev/null || true
  fi

  ok "Docker installed"
}

# ----------------------------------------------------------
# Verify Docker Compose
# ----------------------------------------------------------
check_compose() {
  if docker compose version &>/dev/null 2>&1; then
    ok "Docker Compose available: $(docker compose version --short 2>/dev/null || echo 'v2')"
  else
    fail "Docker Compose not found. Install Docker Desktop (mac) or docker-compose-plugin (linux)."
  fi
}

# ----------------------------------------------------------
# Clone or locate repo
# ----------------------------------------------------------
setup_repo() {
  # If we're already inside the repo (script run from repo dir)
  if [ -f "./docker-compose.yml" ] && [ -f "./.env.example" ]; then
    HIVEMIND_DIR="$(pwd)"
    ok "Using existing repo: $HIVEMIND_DIR"
    return
  fi

  if [ -d "$HIVEMIND_DIR" ] && [ -f "$HIVEMIND_DIR/docker-compose.yml" ]; then
    ok "Hivemind already cloned: $HIVEMIND_DIR"
    return
  fi

  if ! command -v git &>/dev/null; then
    fail "git is required. Install it first."
  fi

  info "Cloning Hivemind to $HIVEMIND_DIR..."
  git clone --branch "$BRANCH" "$REPO_URL" "$HIVEMIND_DIR"
  ok "Cloned"
}

# ----------------------------------------------------------
# Generate secrets
# ----------------------------------------------------------
generate_secret() {
  openssl rand -hex 32 2>/dev/null || LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 64
}

generate_short_secret() {
  openssl rand -hex 16 2>/dev/null || LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 32
}

# ----------------------------------------------------------
# Configure .env
# ----------------------------------------------------------
setup_env() {
  cd "$HIVEMIND_DIR"

  if [ -f ".env" ]; then
    warn ".env already exists — skipping generation (delete it to regenerate)"
    return
  fi

  info "Generating .env with fresh secrets..."

  # Active Record Encryption keys
  local ar_primary
  local ar_deterministic
  local ar_salt
  ar_primary="$(generate_secret)"
  ar_deterministic="$(generate_secret)"
  ar_salt="$(generate_secret)"

  # Rails master key
  local master_key
  master_key="$(generate_short_secret)"

  # Docker socket GID
  local docker_gid=0
  if [ "$OS" = "linux" ]; then
    docker_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo 0)"
  elif [ "$OS" = "mac" ]; then
    docker_gid="$(stat -f '%g' /var/run/docker.sock 2>/dev/null || echo 0)"
  fi

  cat > .env <<EOF
# ============================================================
# Hivemind 🐝 — Generated by install.sh on $(date -u +"%Y-%m-%d %H:%M UTC")
# ============================================================
# Manage API keys, channels, and integrations in Mission Control → Integrations.

# Active Record Encryption (required for Vault)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$ar_primary
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$ar_deterministic
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$ar_salt

# Rails
RAILS_MASTER_KEY=$master_key

# Docker
DOCKER_GID=$docker_gid
EOF

  # Also write master key file for Rails
  mkdir -p config
  echo -n "$master_key" > config/master.key
  chmod 600 config/master.key

  ok "Generated .env and config/master.key"
}

# ----------------------------------------------------------
# Create shared workspace directory
# ----------------------------------------------------------
setup_shared_workspace() {
  local shared_dir="$HOME/hivemind-agents-shared"
  if [ ! -d "$shared_dir" ]; then
    mkdir -p "$shared_dir"
    ok "Created shared workspace: $shared_dir"
  else
    ok "Shared workspace exists: $shared_dir"
  fi
}

# ----------------------------------------------------------
# Build and start
# ----------------------------------------------------------
build_and_start() {
  cd "$HIVEMIND_DIR"

  info "Building containers (this may take a few minutes on first run)..."
  docker compose build

  info "Starting Hivemind..."
  docker compose up -d

  # Wait for Rails to be healthy
  echo -n "Waiting for Hivemind to be ready..."
  local attempts=0
  while ! curl -sf http://localhost:3001 &>/dev/null; do
    sleep 3
    echo -n "."
    attempts=$((attempts + 1))
    if [ $attempts -gt 40 ]; then
      echo ""
      warn "Taking longer than expected. Check logs with: docker compose logs rails"
      return
    fi
  done
  echo ""
  ok "Hivemind is running!"
}

# ----------------------------------------------------------
# Done
# ----------------------------------------------------------
print_success() {
  echo ""
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${GREEN}🐝 Hivemind is ready!${NC}"
  echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${BOLD}Open:${NC}      http://localhost:3001"
  echo -e "  ${BOLD}Location:${NC}  $HIVEMIND_DIR"
  echo -e "  ${BOLD}Logs:${NC}      cd $HIVEMIND_DIR && docker compose logs -f"
  echo -e "  ${BOLD}Stop:${NC}      cd $HIVEMIND_DIR && docker compose down"
  echo -e "  ${BOLD}Restart:${NC}   cd $HIVEMIND_DIR && docker compose up -d"
  echo ""
  echo -e "  ${CYAN}Next: Create your account and add your first agent in Mission Control.${NC}"
  echo -e "  ${CYAN}Add API keys and integrations under Settings → Integrations.${NC}"
  echo ""
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------
main() {
  header
  detect_os
  install_docker
  check_compose
  setup_repo
  setup_env
  setup_shared_workspace
  build_and_start
  print_success
}

main "$@"
