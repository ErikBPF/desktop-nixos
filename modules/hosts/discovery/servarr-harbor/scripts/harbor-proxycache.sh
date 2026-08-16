#!/usr/bin/env bash
# Create the Docker Hub pull-through proxy-cache project in Harbor (idempotent).
# Run ON discovery AFTER harbor-setup.sh has Harbor healthy. The k3s nodes then
# mirror docker.io through https://harbor.<domain>/v2/dockerhub (see the runbook).
#
#   ssh -p 2222 erik@discovery 'bash /home/erik/servarr/machines/discovery/scripts/harbor-proxycache.sh'
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="${HARBOR_RUNTIME_DIR:-$DIR}"
ENV_FILE="$RUNTIME_DIR/.env"
API="http://localhost:8085/api/v2.0"          # local API; no TLS/DNS dependency
ADMIN="admin"
PROJECT="dockerhub"
REGISTRY_NAME="docker-hub"

PW="$(grep -E '^HARBOR_ADMIN_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
[ -n "$PW" ] || { echo "❌ HARBOR_ADMIN_PASSWORD missing in $ENV_FILE"; exit 1; }
AUTH=(-u "${ADMIN}:${PW}")

# Optional Docker Hub creds (lift the anonymous pull rate limit). Leave blank for
# anonymous proxying.
HUB_USER="$(grep -E '^DOCKERHUB_USER=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"
HUB_PASS="$(grep -E '^DOCKERHUB_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true)"

echo ":: waiting for Harbor API"
for i in $(seq 1 30); do
  curl -fsS "${AUTH[@]}" "$API/health" >/dev/null 2>&1 && break
  sleep 3
done

# 1) registry endpoint (docker-hub) — create if absent
registry_id() { curl -fsS "${AUTH[@]}" "$API/registries?name=${REGISTRY_NAME}" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
RID="$(registry_id || true)"
if [ -z "$RID" ]; then
  echo ":: creating registry endpoint '${REGISTRY_NAME}'"
  cred='"credential":{"access_key":"","access_secret":"","type":"basic"}'
  [ -n "$HUB_USER" ] && cred="\"credential\":{\"access_key\":\"${HUB_USER}\",\"access_secret\":\"${HUB_PASS}\",\"type\":\"basic\"}"
  curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' "$API/registries" \
    -d "{\"name\":\"${REGISTRY_NAME}\",\"type\":\"docker-hub\",\"url\":\"https://hub.docker.com\",${cred},\"insecure\":false}"
  RID="$(registry_id)"
else
  echo ":: registry '${REGISTRY_NAME}' exists (id=$RID)"
fi

# 2) proxy-cache project (public) — create if absent
if curl -fsS "${AUTH[@]}" "$API/projects?name=${PROJECT}" | grep -q "\"name\":\"${PROJECT}\""; then
  echo ":: project '${PROJECT}' exists"
else
  echo ":: creating public proxy-cache project '${PROJECT}' (registry_id=$RID)"
  curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' "$API/projects" \
    -d "{\"project_name\":\"${PROJECT}\",\"registry_id\":${RID},\"public\":true,\"metadata\":{\"public\":\"true\"}}"
fi

echo ":: done — pull-through ready: docker.io/library/busybox → harbor.<domain>/${PROJECT}/library/busybox"
