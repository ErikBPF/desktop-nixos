#!/usr/bin/env bash
# =============================================================================
# backup-volumes.sh — Restic backup for all Discovery Docker volumes + databases
#
# Backs up to Discovery (192.168.10.220) via SFTP.
#
# Usage: ./backup-volumes.sh
#
# Environment (set in .env or export before running):
#   RESTIC_PASSWORD    — repo encryption password (required)
#   RESTIC_REPOSITORY  — restic repo (default: sftp:erik@192.168.10.220:/home/erik/backups/discovery)
#   POSTGRES_USER      — postgres superuser (default: homelab)
#
# Retention policy: 3 daily, 6 weekly, 12 monthly
# =============================================================================
set -euo pipefail

RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-sftp:erik@192.168.10.220:/home/erik/backups/discovery}"
export RESTIC_REPOSITORY
export RESTIC_PASSWORD="${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set}"

POSTGRES_CONTAINER="postgres"
POSTGRES_USER="${POSTGRES_USER:-homelab}"
STAGING="/tmp/discovery-backup-staging"

KEEP_DAILY=3
KEEP_WEEKLY=6
KEEP_MONTHLY=12

cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

# --- Init repo if needed ---
if ! restic snapshots &>/dev/null; then
  echo "=== Initializing restic repository ==="
  restic init
fi

echo "=== Discovery Restic Backup ==="
echo "Repo: $RESTIC_REPOSITORY"
echo "Retention: ${KEEP_DAILY}d / ${KEEP_WEEKLY}w / ${KEEP_MONTHLY}m"
echo ""

mkdir -p "$STAGING/databases" "$STAGING/volumes"

# --- Database dumps ---
echo "--- Database dumps ---"
if docker ps --format '{{.Names}}' | grep -qx "$POSTGRES_CONTAINER"; then
  docker exec "$POSTGRES_CONTAINER" pg_dumpall -U "$POSTGRES_USER" \
    > "$STAGING/databases/postgres_all.sql"
  echo "  pg: $(du -sh "$STAGING/databases/postgres_all.sql" | cut -f1)"
else
  echo "  pg: skipped (not running)"
fi

if docker ps --format '{{.Names}}' | grep -qx "redis"; then
  docker exec redis redis-cli BGSAVE >/dev/null 2>&1 || true
  sleep 1
  docker cp redis:/data/dump.rdb "$STAGING/databases/redis_dump.rdb" 2>/dev/null \
    && echo "  redis: $(du -sh "$STAGING/databases/redis_dump.rdb" | cut -f1)" \
    || echo "  redis: skipped (no dump.rdb)"
else
  echo "  redis: skipped (not running)"
fi

# --- Export volumes to staging ---
echo ""
echo "--- Exporting Docker volumes ---"
VOLUMES=$(docker volume ls --format '{{.Name}}' | grep -v '^[0-9a-f]\{64\}$' | sort)

for vol in $VOLUMES; do
  docker run --rm \
    -v "${vol}:/source:ro" \
    -v "$STAGING/volumes:/out" \
    alpine tar cf "/out/${vol}.tar" -C /source . 2>/dev/null
  echo "  ${vol} ($(du -sh "$STAGING/volumes/${vol}.tar" | cut -f1))"
done

# --- Restic backup ---
echo ""
echo "--- Restic backup ---"
restic backup "$STAGING" \
  --host discovery \
  --tag discovery \
  --verbose

# --- Prune ---
echo ""
echo "--- Pruning (keep ${KEEP_DAILY}d/${KEEP_WEEKLY}w/${KEEP_MONTHLY}m) ---"
restic forget \
  --keep-daily "$KEEP_DAILY" \
  --keep-weekly "$KEEP_WEEKLY" \
  --keep-monthly "$KEEP_MONTHLY" \
  --prune \
  --host discovery

# --- Summary ---
echo ""
echo "=== Done ==="
restic snapshots --host discovery --compact
echo ""
restic stats --mode raw-data 2>/dev/null || true
