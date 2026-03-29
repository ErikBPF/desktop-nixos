#!/usr/bin/env bash
# =============================================================================
# validate-health.sh — Discovery container health validation
# Machine: Discovery (Bazzite — AI Workstation)
# Checks that all critical Discovery containers are running and healthy
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=== Discovery Container Health Validation ==="
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker not found${NC}"
    exit 1
fi

# Critical services for Discovery
CRITICAL_SERVICES=(
    "llama-chat"
    "tailscale"
    "hermes-agent"
)

# Check network
echo "Checking network..."
if docker network ls --format '{{.Name}}' | grep -q "^homelab-net$"; then
    echo -e "  ${GREEN}✓${NC} homelab-net network exists"
else
    echo -e "  ${RED}✗${NC} homelab-net network missing"
fi
echo ""

# Check GPU availability
echo "Checking GPU..."
if [ -e /dev/kfd ]; then
    echo -e "  ${GREEN}✓${NC} AMD KFD device available"
else
    echo -e "  ${RED}✗${NC} AMD KFD device not found"
fi
if [ -d /dev/dri ]; then
    echo -e "  ${GREEN}✓${NC} DRI devices available"
else
    echo -e "  ${RED}✗${NC} DRI devices not found"
fi
echo ""

# Check containers
echo "Checking containers..."
RUNNING=()
HEALTHY=()
UNHEALTHY=()
STOPPED=()

for service in "${CRITICAL_SERVICES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
        status=$(docker inspect --format='{{.State.Status}}' "${service}" 2>/dev/null || echo "not_found")

        case "${status}" in
            "running")
                RUNNING+=("${service}")

                health=$(docker inspect --format='{{.State.Health.Status}}' "${service}" 2>/dev/null || echo "unknown")
                if [ "${health}" = "healthy" ]; then
                    HEALTHY+=("${service}")
                    echo -e "  ${GREEN}✓${NC} ${service} (healthy)"
                elif [ "${health}" = "starting" ]; then
                    HEALTHY+=("${service}")
                    echo -e "  ${BLUE}○${NC} ${service} (starting)"
                else
                    UNHEALTHY+=("${service}")
                    echo -e "  ${YELLOW}⚠${NC} ${service} (status: ${status}, health: ${health})"
                fi
                ;;
            "exited"|"dead")
                STOPPED+=("${service}")
                echo -e "  ${RED}✗${NC} ${service} (stopped)"
                ;;
            *)
                echo -e "  ${YELLOW}⚠${NC} ${service} (status: ${status})"
                ;;
        esac
    else
        echo -e "  ${YELLOW}⚠${NC} ${service} (not found)"
    fi
done
echo ""

# Report results
echo "=== Summary ==="
echo -e "Running: ${#RUNNING[@]}"
echo -e "Healthy: ${#HEALTHY[@]}"
echo -e "Unhealthy: ${#UNHEALTHY[@]}"
echo -e "Stopped: ${#STOPPED[@]}"
echo ""

if [ ${#UNHEALTHY[@]} -eq 0 ] && [ ${#STOPPED[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All critical Discovery containers are healthy${NC}"
    exit 0
else
    if [ ${#UNHEALTHY[@]} -gt 0 ]; then
        echo -e "${RED}Unhealthy containers:${NC}"
        for s in "${UNHEALTHY[@]}"; do
            echo "  - $s"
        done
        echo ""
        echo "Troubleshooting:"
        echo "  docker logs ${UNHEALTHY[0]}"
    fi
    if [ ${#STOPPED[@]} -gt 0 ]; then
        echo -e "${YELLOW}Stopped containers:${NC}"
        for s in "${STOPPED[@]}"; do
            echo "  - $s"
        done
    fi
    echo ""
    echo -e "${YELLOW}Some containers need attention${NC}"
    exit 1
fi
