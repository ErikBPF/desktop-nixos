# shellcheck shell=bash
set -euo pipefail

[[ $# -eq 3 && $1 =~ ^run(-stopped)?$ && $2 =~ ^[0-9a-f]{64}$ && $3 =~ ^[0-9a-f]{64}$ ]] || {
  echo "usage: kepler-collision-postgres-evidence run|run-stopped INVENTORY_SHA256 SOURCE_CONTAINER_ID" >&2
  exit 2
}

inventory_sha=$2
expected_id=$3
container=postgres
backup_base=/fast/backups/kepler-collision-k1
if [[ -n ${KEPLER_RECOVERY_TEST_ROOT:-} ]]; then
  [[ -n ${BATS_TEST_TMPDIR:-} && $KEPLER_RECOVERY_TEST_ROOT == "$BATS_TEST_TMPDIR"/* ]] || {
    echo "postgres evidence halted: invalid test root" >&2
    exit 2
  }
  backup_base=$KEPLER_RECOVERY_TEST_ROOT
fi
root="$backup_base/postgres/$inventory_sha"
artifact="$root/retained-databases.tar"
work="$root/.work"
disposable="kepler-k1-postgres-restore-${inventory_sha:0:12}"
volume="${disposable}-data"
created=false
volume_created=false
source_started=false
umask 077

cleanup() {
  if [[ $created == true ]]; then
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
  echo "postgres evidence halted: source container ID drift" >&2
  exit 2
}
source_state=$(podman inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
if [[ $1 == run && $source_state != running ]]; then
  echo "postgres evidence halted: exact source container is not running" >&2
  exit 2
elif [[ $1 == run-stopped ]]; then
  [[ $source_state == exited ]] || {
    echo "postgres evidence halted: exact source container is not exited" >&2
    exit 2
  }
  podman start "$expected_id" >/dev/null 2>&1
  source_started=true
  for _ in $(seq 1 60); do
    podman exec "$expected_id" pg_isready >/dev/null 2>&1 && break
    sleep 1
  done
  podman exec "$expected_id" pg_isready >/dev/null 2>&1
fi
image_id=$(podman inspect --format '{{.Image}}' "$container" 2>/dev/null)
[[ $image_id =~ ^(sha256:)?[0-9a-f]{64}$ ]] || {
  echo "postgres evidence halted: source image identity unavailable" >&2
  exit 2
}
[[ $image_id == sha256:* ]] || image_id="sha256:$image_id"

install -d -m 0700 "$root"
rm -rf -- "$work"
install -d -m 0700 "$work/source" "$work/restored"
# PostgreSQL emits fresh psql safety tokens on every plain dump. They are
# transport metadata, not schema or row content, so exclude only those exact
# command lines from logical comparison while retaining the raw backup.
normalized_dump_sha() {
  sed -e '/^\\restrict [A-Za-z0-9_-]\+$/d' -e '/^\\unrestrict [A-Za-z0-9_-]\+$/d' "$1" \
    | sha256sum | cut -d' ' -f1
}
# Names and owners are metadata. Credentials remain expanded only inside Postgres.
podman exec "$container" sh -ceu 'exec psql -Atq -F "|" -U "$POSTGRES_USER" -d postgres -c "select datname, pg_get_userbyid(datdba) from pg_database where datallowconn order by datname"' >"$work/inventory.raw" 2>/dev/null
python3 - "$work/inventory.raw" "$work/inventory.json" "$work/retained" <<'PY'
import json
import pathlib
import re
import sys

raw, inventory_path, retained_path = map(pathlib.Path, sys.argv[1:])
safe = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
items = []
for line in raw.read_text().splitlines():
    parts = line.split("|")
    if len(parts) != 2 or not all(safe.fullmatch(part) for part in parts):
        raise SystemExit("database evidence halted: unsafe database identity")
    items.append({"name": parts[0], "owner": parts[1]})
if len(items) != len({item["name"] for item in items}) or [item["name"] for item in items].count("airflow") != 1:
    raise SystemExit("database evidence halted: exact Airflow inventory unavailable")
inventory_path.write_text(json.dumps(items, sort_keys=True, separators=(",", ":")) + "\n")
retained_path.write_text("".join(f'{item["name"]}|{item["owner"]}\n' for item in items if item["name"] != "airflow"))
PY
while IFS='|' read -r name owner; do
  [[ -n $name && -n $owner ]] || continue
  podman exec "$container" sh -ceu 'exec pg_dump --clean --if-exists --no-owner --no-privileges --format=plain -U "$POSTGRES_USER" -d "$1"' sh "$name" >"$work/source/$name.sql" 2>/dev/null
done <"$work/retained"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf "$artifact" -C "$work" source
artifact_sha=$(sha256sum "$artifact" | cut -d' ' -f1)
artifact_bytes=$(stat -c %s "$artifact")

podman volume create "$volume" >/dev/null 2>&1
volume_created=true
podman create --network none --name "$disposable" \
  --mount "type=volume,src=$volume,dst=/var/lib/postgresql" \
  --env POSTGRES_HOST_AUTH_METHOD=trust "$image_id" >/dev/null 2>&1
created=true
podman start "$disposable" >/dev/null 2>&1
for _ in $(seq 1 60); do
  podman exec "$disposable" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
podman exec "$disposable" pg_isready -U postgres >/dev/null 2>&1
declare -A owners=()
while IFS='|' read -r name owner; do
  [[ -n $name && -n $owner ]] || continue
  if [[ $owner != postgres && ! -v owners[$owner] ]]; then
    podman exec "$disposable" createuser -U postgres "$owner" >/dev/null 2>&1
    owners[$owner]=1
  fi
  if [[ $name != postgres ]]; then
    podman exec "$disposable" createdb -U postgres -O "$owner" "$name" >/dev/null 2>&1
  fi
  podman exec --interactive "$disposable" psql -v ON_ERROR_STOP=1 -U postgres -d "$name" <"$work/source/$name.sql" >/dev/null 2>&1
  podman exec "$disposable" pg_dump --clean --if-exists --no-owner --no-privileges --format=plain -U postgres -d "$name" >"$work/restored/$name.sql" 2>/dev/null
  [[ $(normalized_dump_sha "$work/source/$name.sql") == $(normalized_dump_sha "$work/restored/$name.sql") ]] || {
    echo "postgres evidence halted: restored logical hash mismatch" >&2
    exit 2
  }
done <"$work/retained"
logical_sha=$(while IFS='|' read -r name _owner; do printf '%s %s\n' "$name" "$(normalized_dump_sha "$work/source/$name.sql")"; done <"$work/retained" | sha256sum | cut -d' ' -f1)
timestamp=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
python3 - "$inventory_sha" "$expected_id" "$artifact_sha" "$artifact_bytes" "$logical_sha" "$timestamp" "$work/inventory.json" "$work/retained" <<'PY'
import json
import pathlib
import sys

inventory_sha, source_id, artifact_sha, artifact_bytes, logical_sha, timestamp, inventory_path, retained_path = sys.argv[1:]
database_inventory = json.loads(pathlib.Path(inventory_path).read_text())
retained_names = [line.split("|", 1)[0] for line in pathlib.Path(retained_path).read_text().splitlines()]
retained = [item for item in database_inventory if item["name"] in retained_names]
inventory_digest = __import__("hashlib").sha256(
    (json.dumps(database_inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()
).hexdigest()
print(json.dumps({
    "captured_at": timestamp,
    "cluster_artifact": {
        "bytes": int(artifact_bytes),
        "created_at": timestamp,
        "sha256": artifact_sha,
    },
    "cluster_restore": {
        "artifact_sha256": artifact_sha,
        "database_inventory_sha256": inventory_digest,
        "logical_sha256": logical_sha,
        "retained_databases": retained_names,
        "status": "passed",
    },
    "database_inventory": database_inventory,
    "inventory_sha256": inventory_sha,
    "retained_databases": retained,
    "retired_databases": ["airflow"],
    "schema": "kepler-collision-database-evidence-v2",
    "source_container_id": source_id,
}, sort_keys=True, separators=(",", ":")))
PY
rm -rf -- "$work"
