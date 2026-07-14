#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'kepler recovery executor halted: %s\n' "$1" >&2
  exit 2
}

usage() {
  printf '%s\n' 'usage: kepler-collision-recovery-executor [--execute] --manifest FILE --manifest-sha256 SHA256 --inventory-sha256 SHA256' >&2
  exit 2
}

execute=false
manifest_file=
manifest_sha256=
inventory_sha256=
while (($#)); do
  case "$1" in
    --execute) execute=true; shift ;;
    --manifest) (($# >= 2)) || usage; manifest_file=$2; shift 2 ;;
    --manifest-sha256) (($# >= 2)) || usage; manifest_sha256=$2; shift 2 ;;
    --inventory-sha256) (($# >= 2)) || usage; inventory_sha256=$2; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$manifest_file" && -r "$manifest_file" ]] || die 'readable manifest required'
[[ "$manifest_sha256" =~ ^[0-9a-f]{64}$ ]] || die 'exact manifest SHA-256 required'
[[ "$inventory_sha256" =~ ^[0-9a-f]{64}$ ]] || die 'exact inventory SHA-256 required'

actions_file=$(mktemp)
trap 'unlink "$actions_file" 2>/dev/null || true' EXIT
python3 - "$manifest_file" "$manifest_sha256" "$inventory_sha256" >"$actions_file" <<'PY'
import hashlib
import json
import re
import sys

def halt(message):
    raise SystemExit(f"kepler recovery executor halted: {message}")

def digest(value):
    canonical = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    return hashlib.sha256(canonical).hexdigest()

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        wrapper = json.load(handle)
except (OSError, json.JSONDecodeError) as error:
    halt(f"invalid manifest: {error}")

if not isinstance(wrapper, dict) or set(wrapper) != {"manifest", "manifest_sha256"}:
    halt("invalid manifest envelope")
manifest = wrapper.get("manifest")
if not isinstance(manifest, dict):
    halt("invalid manifest body")
if wrapper["manifest_sha256"] != digest(manifest) or wrapper["manifest_sha256"] != sys.argv[2]:
    halt("manifest SHA-256 mismatch")
if manifest.get("schema") != "kepler-retirement-approval-manifest-v1":
    halt("unsupported manifest schema")
if manifest.get("inventory_sha256") != sys.argv[3]:
    halt("inventory SHA-256 mismatch")
actions = manifest.get("actions")
if not isinstance(actions, list) or not actions:
    halt("exact non-empty action list required")

hex64 = re.compile(r"[0-9a-f]{64}")
image = re.compile(r"sha256:[0-9a-f]{64}")
volume = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*_airflow_(?:config|logs)")
paths = {
    "/bulk/git",
    "/fast/apps/airflow/dags",
    "/fast/apps/airflow/plugins",
    "/fast/apps/gitlab/config",
    "/fast/apps/gitlab/logs",
    "/fast/apps/gitlab-runner",
}

for action in actions:
    if not isinstance(action, dict):
        halt("invalid action")
    kind, resource, command = action.get("kind"), action.get("resource"), action.get("command")
    if not isinstance(kind, str) or not isinstance(resource, str) or not isinstance(command, list):
        halt("invalid action fields")
    if any(character in resource for character in "\t\r\n\0"):
        halt("invalid resource characters")
    if len(command) != 4 or command[:3] != ["just", "kepler-recovery-retire-exact", kind]:
        halt("action command/resource mismatch")
    target = command[3]
    if not isinstance(target, str) or any(character in target for character in "\t\r\n\0"):
        halt("invalid exact target")
    if kind != "container" and target != resource:
        halt("action command/resource mismatch")
    allowed = (
        (kind == "container" and hex64.fullmatch(target))
        or (kind == "volume" and (volume.fullmatch(target) or target == "orchestration_restate_data"))
        or (kind == "path" and target in paths)
        or (kind == "artifact" and target == "/fast/ai-models/f5-tts")
        or (kind == "image" and image.fullmatch(target))
        or (kind == "database" and target == "airflow")
    )
    if not allowed:
        halt(f"resource outside exact executor allowlist: {kind}")
    print(f"{kind}\t{target}")
PY

declare -a kinds=()
declare -a resources=()
while IFS=$'\t' read -r kind resource; do
  [[ -n "$kind" && -n "$resource" ]] || die 'invalid preflight output'
  kinds+=("$kind")
  resources+=("$resource")
done <"$actions_file"
((${#kinds[@]} > 0)) || die 'empty preflight output'

for index in "${!kinds[@]}"; do
  kind=${kinds[$index]}
  resource=${resources[$index]}
  if ! $execute; then
    printf 'DRY-RUN %s %s\n' "$kind" "$resource"
    continue
  fi
  case "$kind" in
    container) podman rm --force "$resource" ;;
    volume) podman volume rm "$resource" ;;
    path) rm --one-file-system --recursive --force -- "$resource" ;;
    artifact) rm --one-file-system --recursive --force -- "$resource" ;;
    image) podman image rm "$resource" ;;
    database)
      podman exec postgres sh -ceu \
        'exec dropdb --if-exists -U "$POSTGRES_USER" airflow' 2>/dev/null
      ;;
    *) die 'internal unsupported action' ;;
  esac
  printf 'DONE %s %s\n' "$kind" "$resource"
done
