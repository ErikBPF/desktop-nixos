#!/usr/bin/env bash
# =============================================================================
# setup.sh — Discovery (24/7 Infrastructure) Setup Script
# 24/7 infrastructure host: networking, monitoring, tunneling, homepage
#
# Usage:
#   bash setup.sh                          # Interactive mode
#   bash setup.sh --non-interactive        # Non-interactive mode (requires .env)
#   bash setup.sh --dry-run                # Show what would be done
#   bash setup.sh --help                   # Show help
# =============================================================================
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${WORKTREE_DIR}/logs/setup.log"
STATE_FILE="${WORKTREE_DIR}/.setup_state"

# Discovery stacks in dependency order
DISCOVERY_STACKS=("networking" "infra" "monitoring" "media" "media-server" "plex" "tunneling" "ai-serving" "tools" "dockhand" "renovate" "shared" "homepage")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================
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
# State Management
# =============================================================================
save_state() {
    local phase="$1"
    local status="$2"
    echo "${phase}|${status}|$(date +%s)" >> "${STATE_FILE}"
}

get_state() {
    local phase="$1"
    if [ -f "${STATE_FILE}" ]; then
        grep "^${phase}|" "${STATE_FILE}" | tail -1 | cut -d'|' -f2
    fi
}

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
    else
        log_info "Docker Compose version: $(docker compose version --short 2>/dev/null || echo 'unknown')"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required prerequisites:"
        for item in "${missing[@]}"; do
            log_error "  - ${item}"
        done
        return 1
    fi

    log_success "All required prerequisites met"
    return 0
}

# =============================================================================
# Helper: source .env
# =============================================================================
source_env() {
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
        fi
    done < "${WORKTREE_DIR}/.env"
}

# =============================================================================
# Phase 1: Initialization & Validation
# =============================================================================
phase1_init() {
    log_info "=== Phase 1: Initialization & Validation ==="

    mkdir -p "${WORKTREE_DIR}/logs"

    if [ ! -f "${WORKTREE_DIR}/.env" ]; then
        log_warn "No .env file found. Creating from .env.example..."
        if [ -f "${WORKTREE_DIR}/.env.example" ]; then
            cp "${WORKTREE_DIR}/.env.example" "${WORKTREE_DIR}/.env"
            log_warn "Please edit ${WORKTREE_DIR}/.env and fill in required values"
            return 1
        else
            log_error "No .env or .env.example found"
            return 1
        fi
    fi

    # Validate essential env vars
    source_env
    local missing=()
    for var in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_PORT HOMELAB_DOMAIN APPS_PATH MEDIA_PATH; do
        local val="${!var:-}"
        if [ -z "$val" ] || [ "$val" = "changeme" ]; then
            missing+=("$var")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Unfilled .env variables:"
        for v in "${missing[@]}"; do
            log_error "  - $v"
        done
        return 1
    fi

    # Auto-generate *arr API keys if empty (must be 32-char lowercase hex)
    local keys_generated=false
    for key_var in SONARR_API_KEY RADARR_API_KEY LIDARR_API_KEY; do
        local val="${!key_var:-}"
        if [ -z "$val" ] || [ "$val" = "changeme" ]; then
            local new_key
            new_key=$(openssl rand -hex 16)
            sed -i "s/^${key_var}=.*/${key_var}=${new_key}/" "${WORKTREE_DIR}/.env"
            log_info "Generated ${key_var} (32-char hex)"
            keys_generated=true
        elif [ ${#val} -ne 32 ]; then
            log_error "${key_var} must be exactly 32 hex characters (got ${#val} chars)"
            log_error "Generate a valid key with: openssl rand -hex 16"
            return 1
        fi
    done

    if [ "$keys_generated" = true ]; then
        log_warn "API keys were auto-generated. Re-sourcing .env..."
        source_env
    fi

    log_success "Environment validation passed"
    save_state "phase1_init" "complete"
    return 0
}

# =============================================================================
# Phase 2: Infrastructure Setup
# =============================================================================
phase2_infra() {
    log_info "=== Phase 2: Infrastructure Setup ==="

    # Create homelab-net external network
    if ! docker network ls --format '{{.Name}}' | grep -q "^homelab-net$"; then
        log_info "Creating homelab-net bridge network..."
        source_env
        docker network create \
            --driver bridge \
            --subnet "${HOMELAB_SUBNET:-172.20.0.0/16}" \
            --gateway "${HOMELAB_GATEWAY:-172.20.0.1}" \
            homelab-net 2>/dev/null || true
        log_success "homelab-net created"
    else
        log_info "homelab-net already exists, skipping"
    fi

    # Start networking stack (SWAG, AdGuard)
    if [ -f "${WORKTREE_DIR}/networking.yml" ]; then
        log_info "Starting networking stack..."
        docker compose -f "${WORKTREE_DIR}/networking.yml" --env-file "${WORKTREE_DIR}/.env" up -d
    fi

    # Start infra stack (Postgres, Redis)
    if [ -f "${WORKTREE_DIR}/infra.yml" ]; then
        log_info "Starting infrastructure stack..."
        docker compose -f "${WORKTREE_DIR}/infra.yml" --env-file "${WORKTREE_DIR}/.env" up -d

        log_info "Waiting for PostgreSQL to be ready..."
        local max_attempts=30
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if docker exec postgres pg_isready -U "${POSTGRES_USER:-postgres}" &> /dev/null; then
                log_success "PostgreSQL is ready"
                break
            fi
            log_info "PostgreSQL not ready yet (attempt ${attempt}/${max_attempts})..."
            sleep 2
            attempt=$((attempt + 1))
        done

        if [ $attempt -gt $max_attempts ]; then
            log_error "PostgreSQL failed to become ready"
            return 1
        fi
    fi

    save_state "phase2_infra" "complete"
    return 0
}

# =============================================================================
# Phase 3: Database Provisioning
# =============================================================================
phase3_db() {
    log_info "=== Phase 3: Database Provisioning ==="

    if [ ! -f "${WORKTREE_DIR}/scripts/provision-db.sql" ]; then
        log_warn "provision-db.sql not found, skipping database provisioning"
        save_state "phase3_db" "skipped"
        return 0
    fi

    log_info "Provisioning databases..."
    docker exec -i postgres psql -U "${POSTGRES_USER:-homelab}" -d postgres < "${WORKTREE_DIR}/scripts/provision-db.sql"

    log_info "Verifying databases..."
    for db in homepage healthchecks litellm langfuse sonarr_main sonarr_log radarr_main radarr_log lidarr_main lidarr_log prowlarr_main prowlarr_log jellystat seerr autobrr; do
        if docker exec postgres psql -U "${POSTGRES_USER:-homelab}" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
            log_success "Database '${db}' exists"
        else
            log_warn "Database '${db}' not found"
        fi
    done

    save_state "phase3_db" "complete"
    return 0
}

# =============================================================================
# Phase 4: Configuration Pre-seeding
# =============================================================================
phase4_config() {
    log_info "=== Phase 4: Configuration Pre-seeding ==="

    source_env
    local BASE="${APPS_PATH:-/opt/homelab/apps}"

    # Create storage directories
    mkdir -p "${BASE}"
    mkdir -p "${MEDIA_PATH:-/mnt/media}"

    # Pre-seed *arr configs with local Postgres connection and API keys
    local arr_apps=("sonarr:8989:sonarr" "radarr:7878:radarr" "lidarr:8686:lidarr" "prowlarr:9696:prowlarr")

    for entry in "${arr_apps[@]}"; do
        IFS=':' read -r app port name <<< "${entry}"
        local app_upper="${app^^}"
        local api_key_var="${app_upper}_API_KEY"
        local api_key="${!api_key_var:-}"
        local main_db="${name}_main"
        local log_db="${name}_log"
        local ssl_port=9898
        local branch="master"
        [ "${app}" = "sonarr" ] && branch="main"
        [ "${app}" = "prowlarr" ] && ssl_port=6969

        mkdir -p "${BASE}/${app}"

        # Only write config.xml if it doesn't exist (don't overwrite running config)
        if [ ! -f "${BASE}/${app}/config.xml" ]; then
            cat > "${BASE}/${app}/config.xml" << XML
<Config>
  <LogLevel>info</LogLevel>
  <UpdateMechanism>Docker</UpdateMechanism>
  <UpdateAutomatically>True</UpdateAutomatically>
  <BindAddress>*</BindAddress>
  <Port>${port}</Port>
  <SslPort>${ssl_port}</SslPort>
  <EnableSsl>False</EnableSsl>
  <SslCertPath></SslCertPath>
  <SslCertPassword></SslCertPassword>
  <UrlBase></UrlBase>
  <LaunchBrowser>False</LaunchBrowser>
  <ApiKey>${api_key}</ApiKey>
  <AuthenticationMethod>Forms</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>${branch}</Branch>
  <InstanceName>${app^}</InstanceName>
  <PostgresUser>${POSTGRES_USER}</PostgresUser>
  <PostgresPassword>${POSTGRES_PASSWORD}</PostgresPassword>
  <PostgresPort>${POSTGRES_PORT}</PostgresPort>
  <PostgresHost>postgres</PostgresHost>
  <PostgresMainDb>${main_db}</PostgresMainDb>
  <PostgresLogDb>${log_db}</PostgresLogDb>
</Config>
XML
            log_success "${app^} config written to ${BASE}/${app}/config.xml"
        else
            log_warn "${app^} config already exists, skipping"
        fi
    done

    # Pre-seed qBittorrent config
    local QBIT_CONF_DIR="${BASE}/qbittorrent/qBittorrent/config"
    local QBIT_CONF_FILE="${QBIT_CONF_DIR}/qBittorrent.conf"

    if [ ! -f "${QBIT_CONF_FILE}" ]; then
        mkdir -p "${QBIT_CONF_DIR}"
        cat > "${QBIT_CONF_FILE}" << 'CONF'
[LegalNotice]
Accepted=true

[Preferences]
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\AuthSubnetWhitelist=172.20.0.0/24, 192.168.10.0/24
WebUI\LocalHostAuth=false
WebUI\Port=9080
WebUI\UseUPnP=false
WebUI\Authentication=false
CONF
        log_success "qBittorrent config written"
    else
        log_warn "qBittorrent config already exists, skipping"
    fi

    # Copy config templates from repo to APPS_PATH (if not already present)
    log_info "Copying config templates..."
    local TEMPLATE_DIR="${WORKTREE_DIR}/config"

    # Autobrr
    if [ -f "${TEMPLATE_DIR}/autobrr/config.toml" ] && [ ! -f "${BASE}/autobrr/config.toml" ]; then
        mkdir -p "${BASE}/autobrr"
        cp "${TEMPLATE_DIR}/autobrr/config.toml" "${BASE}/autobrr/"
        log_success "Autobrr config copied"
    fi

    # Recyclarr
    if [ -f "${TEMPLATE_DIR}/recyclarr/recyclarr.yml" ] && [ ! -f "${BASE}/recyclarr/recyclarr.yml" ]; then
        mkdir -p "${BASE}/recyclarr"
        cp "${TEMPLATE_DIR}/recyclarr/recyclarr.yml" "${BASE}/recyclarr/"
        log_success "Recyclarr config copied"
    fi

    save_state "phase4_config" "complete"
    return 0
}

# =============================================================================
# Phase 5: Stack Deployment
# =============================================================================
phase5_stacks() {
    log_info "=== Phase 5: Stack Deployment ==="

    # networking and infra already started in phase2
    local remaining_stacks=("monitoring" "media" "media-server" "plex" "tunneling" "ai-serving" "tools" "dockhand" "renovate" "shared" "homepage")

    for stack in "${remaining_stacks[@]}"; do
        local compose_file="${WORKTREE_DIR}/${stack}.yml"
        if [ -f "${compose_file}" ]; then
            log_info "Starting ${stack} stack..."
            docker compose -f "${compose_file}" --env-file "${WORKTREE_DIR}/.env" up -d

            # Give media stack time to initialize
            if [ "${stack}" = "media" ]; then
                log_info "Waiting for media stack to initialize..."
                sleep 10
            fi
        else
            log_warn "${stack}.yml not found, skipping"
        fi
    done

    save_state "phase5_stacks" "complete"
    return 0
}

# =============================================================================
# Phase 6: Post-Setup Validation
# =============================================================================
phase6_validate() {
    log_info "=== Phase 6: Post-Setup Validation ==="

    log_info "Checking container health..."
    local unhealthy=()
    local running=0

    for stack in "${DISCOVERY_STACKS[@]}"; do
        if [ ! -f "${WORKTREE_DIR}/${stack}.yml" ]; then
            continue
        fi
        while IFS= read -r container; do
            [ -z "${container}" ] && continue
            running=$((running + 1))
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "none")
            if [ "${health}" = "unhealthy" ]; then
                unhealthy+=("${container}")
            fi
        done < <(docker compose -f "${WORKTREE_DIR}/${stack}.yml" --env-file "${WORKTREE_DIR}/.env" ps -q 2>/dev/null || true)
    done

    log_info "Running containers: ${running}"
    if [ ${#unhealthy[@]} -gt 0 ]; then
        log_warn "Unhealthy containers: ${unhealthy[*]}"
    else
        log_success "No unhealthy containers detected"
    fi

    source_env
    log_info "=== Setup Summary ==="
    log_info "Key access URLs:"
    log_info "  - Grafana:      https://grafana.${HOMELAB_DOMAIN:-pastelariadev.com}"
    log_info "  - Prometheus:   http://localhost:9090"
    log_info "  - Uptime Kuma:  http://localhost:3001"
    log_info "  - Homepage:     http://localhost:3000"
    log_info "  - Sonarr:       http://localhost:8989"
    log_info "  - Radarr:       http://localhost:7878"
    log_info "  - Lidarr:       http://localhost:8686"
    log_info "  - Prowlarr:     http://localhost:9696"
    log_info "  - qBittorrent:  http://localhost:9080"
    log_info "  - Jellyfin:     http://localhost:8096"
    log_info "  - Plex:         http://localhost:32400/web"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Check stack health: bash scripts/validate-health.sh"
    log_info "  2. Configure Cloudflare tunnel token in .env"
    log_info "  3. Set up Grafana dashboards"
    log_info "  4. Configure Prowlarr indexers and connect to *arr apps"
    log_info "  5. Add root folders in Sonarr/Radarr/Lidarr"

    save_state "phase6_validate" "complete"
    return 0
}

# =============================================================================
# Help
# =============================================================================
show_help() {
    cat << EOF
setup.sh — Discovery (24/7 Infrastructure) Setup Script

Usage: bash setup.sh [OPTIONS]

Options:
  --non-interactive    Run without prompts (requires .env to be filled)
  --dry-run            Show what would be done without making changes
  --help               Show this help message

Phases:
  1. Initialization & Validation (env check, API key generation)
  2. Infrastructure Setup (homelab-net, networking, infra)
  3. Database Provisioning (all app databases)
  4. Configuration Pre-seeding (arr configs, qBittorrent)
  5. Stack Deployment (monitoring, media, media-server, plex, tunneling, etc.)
  6. Post-Setup Validation (health checks, summary)

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --dry-run)
            log_info "Dry run mode — showing what would be done"
            log_info ""
            log_info "Phase 1: Initialization & Validation"
            log_info "  - Check for .env file"
            log_info "  - Validate environment variables"
            log_info "  - Auto-generate *arr API keys if empty (32-char hex)"
            log_info ""
            log_info "Phase 2: Infrastructure Setup"
            log_info "  - Create homelab-net bridge network"
            log_info "  - Start networking stack (SWAG, AdGuard)"
            log_info "  - Start infra stack (PostgreSQL, Redis)"
            log_info ""
            log_info "Phase 3: Database Provisioning"
            log_info "  - Create all app databases via provision-db.sql"
            log_info ""
            log_info "Phase 4: Configuration Pre-seeding"
            log_info "  - Generate Sonarr/Radarr/Lidarr/Prowlarr config.xml (PostgresHost=postgres)"
            log_info "  - Generate qBittorrent.conf"
            log_info ""
            log_info "Phase 5: Stack Deployment"
            log_info "  - monitoring, media, media-server, plex, tunneling, ai-serving"
            log_info "  - tools, dockhand, renovate, shared, homepage"
            log_info ""
            log_info "Phase 6: Post-Setup Validation"
            log_info "  - Check container health"
            log_info "  - Generate setup summary"
            exit 0
            ;;
        --status)
            if [ -f "${STATE_FILE}" ]; then
                cat "${STATE_FILE}"
            else
                echo "No setup state found"
            fi
            exit 0
            ;;
    esac

    if ! check_prerequisites; then
        exit 1
    fi

    phase1_init || exit 1
    phase2_infra || exit 1
    phase3_db || exit 1
    phase4_config || exit 1
    phase5_stacks || exit 1
    phase6_validate || exit 1

    log_success "=== Discovery Setup Complete ==="
    log_info "See ${LOG_FILE} for detailed logs"
}

main "$@"
