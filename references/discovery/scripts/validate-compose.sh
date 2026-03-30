#!/usr/bin/env bash
# =============================================================================
# validate-compose.sh — Validate all Discovery compose files
# Host: Discovery (Debian — 24/7 Infrastructure)
#
# Checks every active service for: logging, healthcheck, restart policy.
# Runs `docker compose config` syntax check when Docker is available.
# Exit 0 = all pass, Exit 1 = any failure
# =============================================================================
set -euo pipefail

HOST_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOST_NAME="Discovery"

# One-shot / cron containers where missing healthcheck is a warning
ONESHOT_SERVICES="docker-prune kometa renovate"

# Services that inherit logging via YAML anchors (<<: *airflow-common etc.)
# Skip logging check for these — validated by docker compose config instead
ANCHOR_INHERITED=""

# Colors
if [[ -t 1 ]]; then
  GREEN='\033[0;32m' RED='\033[0;31m' YELLOW='\033[0;33m'
  CYAN='\033[0;36m' BOLD='\033[1m' RESET='\033[0m'
else
  GREEN='' RED='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0

parse_services() {
  awk '
    /^services:/ { in_services=1; next }
    in_services && /^[^ #]/ { exit }
    in_services && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ {
      name = $0; sub(/:.*/, "", name); gsub(/^[[:space:]]+/, "", name); print name
    }
  ' "$1"
}

service_has_key() {
  local file="$1" service="$2" key="$3"
  awk -v svc="$service" -v key="$key" '
    /^services:/ { in_services=1; next }
    in_services && /^[^ #]/ { in_services=0 }
    in_services && /^  [a-zA-Z_]/ {
      name = $0; sub(/:.*/, "", name); gsub(/^[[:space:]]+/, "", name)
      in_target = (name == svc)
    }
    in_target && /^    [a-zA-Z]/ {
      k = $0; sub(/:.*/, "", k); gsub(/^[[:space:]]+/, "", k)
      if (k == key) { found=1; exit }
    }
    END { exit !found }
  ' "$file"
}

is_oneshot() {
  for os in $ONESHOT_SERVICES; do [[ "$1" == "$os" ]] && return 0; done
  return 1
}

printf "${BOLD}=== %s Compose Validation ===${RESET}\n\n" "$HOST_NAME"

for yml in "$HOST_DIR"/*.yml; do
  [[ ! -f "$yml" ]] && continue
  filename="$(basename "$yml")"

  printf "${CYAN}${BOLD}%-30s${RESET}\n" "$filename"

  services=$(parse_services "$yml")
  [[ -z "$services" ]] && { printf "  ${YELLOW}(no active services)${RESET}\n\n"; continue; }

  while IFS= read -r svc; do
    svc_fail=0
    has_logging="FAIL"; has_health="FAIL"; has_restart="FAIL"

    service_has_key "$yml" "$svc" "logging" && has_logging="PASS"
    # Skip logging check for services inheriting via YAML anchors
    if [[ "$has_logging" == "FAIL" ]]; then
      for ai in $ANCHOR_INHERITED; do [[ "$svc" == "$ai" ]] && { has_logging="PASS"; break; }; done
    fi
    [[ "$has_logging" == "FAIL" ]] && svc_fail=1

    if service_has_key "$yml" "$svc" "healthcheck"; then
      has_health="PASS"
    elif is_oneshot "$svc"; then
      has_health="WARN"; TOTAL_WARN=$((TOTAL_WARN + 1))
    else
      has_health="FAIL"; svc_fail=1
    fi

    service_has_key "$yml" "$svc" "restart" && has_restart="PASS"
    # Check <<: *restart merge via x-restart anchor
    [[ "$has_restart" == "FAIL" ]] && grep -q '<<: \*restart' "$yml" && has_restart="PASS"
    [[ "$has_restart" == "FAIL" ]] && svc_fail=1

    color_l="${GREEN}"; [[ "$has_logging" != "PASS" ]] && color_l="${RED}"
    color_h="${GREEN}"; [[ "$has_health" == "FAIL" ]] && color_h="${RED}"; [[ "$has_health" == "WARN" ]] && color_h="${YELLOW}"
    color_r="${GREEN}"; [[ "$has_restart" != "PASS" ]] && color_r="${RED}"

    printf "  %-25s ${color_l}%s${RESET}  ${color_h}%s${RESET}  ${color_r}%s${RESET}\n" "$svc" "$has_logging" "$has_health" "$has_restart"

    [[ $svc_fail -eq 1 ]] && TOTAL_FAIL=$((TOTAL_FAIL + 1)) || TOTAL_PASS=$((TOTAL_PASS + 1))
  done <<< "$services"
  printf "\n"
done

# Docker compose syntax check
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  printf "${BOLD}=== Docker Compose Syntax ===${RESET}\n\n"
  for yml in "$HOST_DIR"/*.yml; do
    [[ ! -f "$yml" ]] && continue
    filename="$(basename "$yml")"
    if docker compose -f "$yml" config --quiet 2>/dev/null; then
      printf "  ${GREEN}PASS${RESET}  %s\n" "$filename"
    else
      printf "  ${YELLOW}WARN${RESET}  %s (syntax issue or missing env vars)\n" "$filename"
    fi
  done
  printf "\n"
fi

printf "${BOLD}=== Summary ===${RESET}\n"
printf "  Pass: ${GREEN}%d${RESET}  Fail: ${RED}%d${RESET}  Warn: ${YELLOW}%d${RESET}\n\n" \
  "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_WARN"

[[ $TOTAL_FAIL -gt 0 ]] && { printf "${RED}${BOLD}VALIDATION FAILED${RESET}\n\n"; exit 1; }
printf "${GREEN}${BOLD}ALL SERVICES PASSED${RESET}\n\n"
