#!/usr/bin/env bash
# =============================================================================
# setup.sh — Discovery (Machine 1) Setup Script
# AI workstation (Bazzite, AMD GPU)
#
# Usage:
#   bash setup.sh                  # Run setup
#   bash setup.sh --dry-run        # Show what would be done
#   bash setup.sh --help           # Show help
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${WORKTREE_DIR}/logs/setup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "${LOG_FILE}")"
    echo "[${timestamp}] [${level}] ${msg}" >> "${LOG_FILE}"

    case "${level}" in
        INFO)  echo -e "${BLUE}[INFO]${NC} ${msg}" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} ${msg}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} ${msg}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${msg}" ;;
    esac
}

log_info()    { log "INFO" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_warn()    { log "WARN" "$@"; }
log_error()   { log "ERROR" "$@"; }

# =============================================================================
# Prerequisite Checks
# =============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    if ! command -v docker &> /dev/null; then
        missing+=("Docker (https://docs.docker.com/engine/install/)")
    else
        log_info "Docker version: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
    fi

    if ! docker compose version &> /dev/null; then
        missing+=("Docker Compose v2 (docker compose plugin)")
    fi

    # Check AMD GPU (ROCm)
    if [ -e /dev/kfd ]; then
        log_success "AMD KFD device found (/dev/kfd)"
    else
        log_warn "/dev/kfd not found — ROCm GPU acceleration will not work"
        missing+=("AMD KFD device (/dev/kfd)")
    fi

    if [ -d /dev/dri ]; then
        log_success "DRI devices found (/dev/dri)"
    else
        log_warn "/dev/dri not found — GPU rendering will not work"
        missing+=("DRI devices (/dev/dri)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites:"
        for item in "${missing[@]}"; do
            log_error "  - ${item}"
        done
        return 1
    fi

    log_success "All prerequisites met"
    return 0
}

# =============================================================================
# Main Setup
# =============================================================================
main() {
    case "${1:-}" in
        --help|-h)
            cat << EOF
setup.sh — Discovery (Machine 1) Setup Script

Usage: bash setup.sh [OPTIONS]

Options:
  --dry-run    Show what would be done
  --help       Show this help message

Steps:
  1. Check prerequisites (ROCm GPU, Docker)
  2. Validate .env file
  3. Create homelab-net network
  4. Start shared stack (Tailscale, Alloy, Syncthing)
  5. Start ai-models stack (llama-chat)
  6. Start hermes-agent stack

EOF
            exit 0
            ;;
        --dry-run)
            log_info "Dry run mode — showing what would be done"
            log_info ""
            log_info "1. Check prerequisites (ROCm GPU at /dev/kfd, /dev/dri, Docker)"
            log_info "2. Validate .env file"
            log_info "3. Create homelab-net bridge network"
            log_info "4. Start shared stack (Tailscale, Alloy, Syncthing, docker-prune)"
            log_info "5. Start ai-models stack (llama-chat with ROCm)"
            log_info "6. Start hermes-agent stack"
            exit 0
            ;;
    esac

    if ! check_prerequisites; then
        exit 1
    fi

    # Validate .env
    if [ ! -f "${WORKTREE_DIR}/.env" ]; then
        if [ -f "${WORKTREE_DIR}/.env.example" ]; then
            cp "${WORKTREE_DIR}/.env.example" "${WORKTREE_DIR}/.env"
            log_warn "Created .env from .env.example — please edit and re-run"
            exit 1
        else
            log_error "No .env or .env.example found"
            exit 1
        fi
    fi

    # Create network
    if ! docker network ls --format '{{.Name}}' | grep -q "^homelab-net$"; then
        log_info "Creating homelab-net bridge network..."
        docker network create --driver bridge homelab-net 2>/dev/null || true
        log_success "homelab-net created"
    else
        log_info "homelab-net already exists"
    fi

    # Start stacks
    local stacks=("shared" "ai-models" "hermes-agent")
    for stack in "${stacks[@]}"; do
        local compose_file="${WORKTREE_DIR}/${stack}.yml"
        if [ -f "${compose_file}" ]; then
            log_info "Starting ${stack} stack..."
            docker compose -f "${compose_file}" --env-file "${WORKTREE_DIR}/.env" up -d
            log_success "${stack} stack started"
        else
            log_warn "${stack}.yml not found, skipping"
        fi
    done

    log_success "=== Discovery Setup Complete ==="
    log_info "Run 'bash scripts/validate-health.sh' to verify container health"
}

main "$@"
