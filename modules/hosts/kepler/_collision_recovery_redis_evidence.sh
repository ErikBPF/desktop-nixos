set -euo pipefail

[[ $# -eq 3 && $1 =~ ^run(-stopped)?$ && $2 =~ ^[0-9a-f]{64}$ && $3 =~ ^[0-9a-f]{64}$ ]] || {
  echo "usage: kepler-collision-redis-evidence run|run-stopped INVENTORY_SHA256 SOURCE_CONTAINER_ID" >&2
  exit 2
}

inventory_sha=$2
expected_id=$3
container=redis
backup_base=/fast/backups/kepler-collision-k1
if [[ -n ${KEPLER_RECOVERY_TEST_ROOT:-} ]]; then
  [[ -n ${BATS_TEST_TMPDIR:-} && $KEPLER_RECOVERY_TEST_ROOT == "$BATS_TEST_TMPDIR"/* ]] || {
    echo "redis evidence halted: invalid test root" >&2
    exit 2
  }
  backup_base=$KEPLER_RECOVERY_TEST_ROOT
fi
root="$backup_base/redis/$inventory_sha"
artifact="$root/dump.rdb"
disposable="kepler-k1-redis-restore-${inventory_sha:0:12}"
volume="${disposable}-data"
container_created=false
volume_created=false
source_started=false
umask 077

cleanup() {
  if [[ $container_created == true ]]; then
    podman rm --force "$disposable" >/dev/null 2>&1 || true
  fi
  if [[ $volume_created == true ]]; then
    podman volume rm "$volume" >/dev/null 2>&1 || true
  fi
  if [[ $source_started == true ]]; then
    podman stop "$expected_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

[[ $(podman inspect --format '{{.Id}}' "$container" 2>/dev/null) == "$expected_id" ]] || {
  echo "redis evidence halted: source container ID drift" >&2
  exit 2
}
source_state=$(podman inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
if [[ $1 == run && $source_state != running ]]; then
  echo "redis evidence halted: exact source container is not running" >&2
  exit 2
elif [[ $1 == run-stopped ]]; then
  [[ $source_state == exited ]] || {
    echo "redis evidence halted: exact source container is not exited" >&2
    exit 2
  }
  podman start "$expected_id" >/dev/null 2>&1
  source_started=true
  for _ in $(seq 1 60); do
    podman exec "$expected_id" redis-cli ping >/dev/null 2>&1 && break
    sleep 1
  done
  podman exec "$expected_id" redis-cli ping >/dev/null 2>&1
fi
image_id=$(podman inspect --format '{{.Image}}' "$container" 2>/dev/null)
[[ $image_id =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "redis evidence halted: source image identity unavailable" >&2
  exit 2
}

install -d -m 0700 "$root"
# Authentication material is expanded and consumed only inside the existing container.
podman exec "$container" sh -ceu 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli SAVE >/dev/null' 2>/dev/null
key_count=$(podman exec "$container" sh -ceu 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli --raw DBSIZE' 2>/dev/null)
[[ $key_count =~ ^[0-9]+$ ]] || {
  echo "redis evidence halted: source count unavailable" >&2
  exit 2
}
podman cp "$container:/data/dump.rdb" "$artifact" >/dev/null 2>&1
artifact_sha=$(sha256sum "$artifact" | cut -d' ' -f1)
artifact_bytes=$(stat -c %s "$artifact")
source_digest=$(podman exec "$container" sh -ceu '
  export REDISCLI_AUTH="$REDIS_PASSWORD"
  redis-cli --scan | LC_ALL=C sort | while IFS= read -r key; do
    printf "%s\\0" "$key"
    redis-cli --raw DUMP "$key"
    printf "\\0"
  done | sha256sum | cut -d" " -f1
' 2>/dev/null)
[[ $source_digest =~ ^[0-9a-f]{64}$ ]] || {
  echo "redis evidence halted: source logical hash unavailable" >&2
  exit 2
}

podman volume create "$volume" >/dev/null 2>&1
volume_created=true
podman create --network none --name "$disposable" --mount "type=volume,src=$volume,dst=/data" "$image_id" >/dev/null 2>&1
container_created=true
podman cp "$artifact" "$disposable:/data/dump.rdb" >/dev/null 2>&1
podman start "$disposable" >/dev/null 2>&1
for _ in $(seq 1 60); do
  podman exec "$disposable" redis-cli ping >/dev/null 2>&1 && break
  sleep 1
done
podman exec "$disposable" redis-cli ping >/dev/null 2>&1
restored_key_count=$(podman exec "$disposable" redis-cli --raw DBSIZE 2>/dev/null)
[[ $restored_key_count == "$key_count" ]] || {
  echo "redis evidence halted: restored count mismatch" >&2
  exit 2
}
restored_digest=$(podman exec "$disposable" sh -ceu '
  redis-cli --scan | LC_ALL=C sort | while IFS= read -r key; do
    printf "%s\\0" "$key"
    redis-cli --raw DUMP "$key"
    printf "\\0"
  done | sha256sum | cut -d" " -f1
' 2>/dev/null)
[[ $restored_digest == "$source_digest" ]] || {
  echo "redis evidence halted: restored logical hash mismatch" >&2
  exit 2
}
timestamp=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
python3 - "$inventory_sha" "$expected_id" "$artifact_sha" "$artifact_bytes" "$key_count" "$source_digest" "$timestamp" <<'PY'
import json
import sys

inventory_sha, source_id, artifact_sha, artifact_bytes, key_count, logical_sha, timestamp = sys.argv[1:]
print(json.dumps({
    "artifact_bytes": int(artifact_bytes),
    "artifact_sha256": artifact_sha,
    "inventory_sha256": inventory_sha,
    "key_count": int(key_count),
    "logical_sha256": logical_sha,
    "resource": "redis",
    "source_container_id": source_id,
    "status": "passed",
    "timestamp": timestamp,
}, sort_keys=True, separators=(",", ":")))
PY
