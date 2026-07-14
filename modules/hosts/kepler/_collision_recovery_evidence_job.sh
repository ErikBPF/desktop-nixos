# shellcheck shell=bash
set -euo pipefail

usage() {
  echo "usage: kepler-collision-evidence-job submit RESOURCE MODE INVENTORY_SHA256 CONTAINER_ID | execute|status|result REQUEST_SHA256" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
operation=$1
backup_base=/fast/backups/kepler-collision-k1
if [[ -n ${KEPLER_RECOVERY_TEST_ROOT:-} ]]; then
  [[ -n ${BATS_TEST_TMPDIR:-} && $KEPLER_RECOVERY_TEST_ROOT == "$BATS_TEST_TMPDIR"/* ]] || {
    echo "evidence job halted: invalid test root" >&2
    exit 2
  }
  backup_base=$KEPLER_RECOVERY_TEST_ROOT
fi
jobs_root="$backup_base/jobs"
umask 077

write_status() {
  printf '{"request_sha256":"%s","state":"%s"}\n' "$request_sha" "$1" >"$status_file.tmp"
  chmod 0600 "$status_file.tmp"
  mv "$status_file.tmp" "$status_file"
}

if [[ $operation == submit ]]; then
  [[ $# -eq 5 ]] || usage
  resource=$2
  mode=$3
  inventory_sha=$4
  container_id=$5
  [[ $resource == postgres || $resource == redis ]] || usage
  [[ $mode == run || $mode == run-stopped ]] || usage
  [[ $inventory_sha =~ ^[0-9a-f]{64}$ && $container_id =~ ^[0-9a-f]{64}$ ]] || usage

  request=$(python3 - "$resource" "$mode" "$inventory_sha" "$container_id" <<'PY'
import json
import sys

resource, mode, inventory_sha, container_id = sys.argv[1:]
print(json.dumps({
    "container_id": container_id,
    "inventory_sha256": inventory_sha,
    "mode": mode,
    "resource": resource,
    "schema": "kepler-collision-evidence-request-v1",
}, sort_keys=True, separators=(",", ":")))
PY
  )
  request_sha=$(printf '%s\n' "$request" | sha256sum | cut -d' ' -f1)
  root="$jobs_root/$request_sha"
  request_file="$root/request.json"
  status_file="$root/status.json"
  install -d -m 0700 "$root"
  if [[ -f $request_file ]] && [[ $(sha256sum "$request_file" | cut -d' ' -f1) != "$request_sha" ]]; then
    echo "evidence job halted: request collision" >&2
    exit 2
  fi
  if [[ ! -f $request_file ]]; then
    printf '%s\n' "$request" >"$request_file.tmp"
    chmod 0600 "$request_file.tmp"
    mv "$request_file.tmp" "$request_file"
  fi
  if [[ -f $status_file ]] && grep -Eq '"state":"(pending|running|passed)"' "$status_file"; then
    state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$status_file")
    printf '{"request_sha256":"%s","state":"%s"}\n' "$request_sha" "$state"
    exit 0
  fi
  write_status pending
  if ! systemctl --user start --no-block "kepler-collision-evidence@$request_sha.service"; then
    write_status failed
    exit 2
  fi
  printf '{"request_sha256":"%s","state":"submitted"}\n' "$request_sha"
  exit 0
fi

[[ $# -eq 2 && $2 =~ ^[0-9a-f]{64}$ ]] || usage
request_sha=$2
root="$jobs_root/$request_sha"
request_file="$root/request.json"
status_file="$root/status.json"
result_file="$root/result.json"
result_tmp="$root/result.json.tmp"

case $operation in
  execute)
    [[ -f $request_file && $(sha256sum "$request_file" | cut -d' ' -f1) == "$request_sha" ]] || {
      echo "evidence job halted: invalid request binding" >&2
      exit 2
    }
    mapfile -t fields < <(python3 - "$request_file" <<'PY'
import json
import sys

request = json.load(open(sys.argv[1]))
if request.get("schema") != "kepler-collision-evidence-request-v1":
    raise SystemExit(2)
print(request["resource"])
print(request["mode"])
print(request["inventory_sha256"])
print(request["container_id"])
PY
    )
    [[ ${#fields[@]} -eq 4 ]] || exit 2
    resource=${fields[0]}
    mode=${fields[1]}
    inventory_sha=${fields[2]}
    container_id=${fields[3]}
    [[ $resource == postgres || $resource == redis ]] || exit 2
    [[ $mode == run || $mode == run-stopped ]] || exit 2
    [[ $inventory_sha =~ ^[0-9a-f]{64}$ && $container_id =~ ^[0-9a-f]{64}$ ]] || exit 2
    install -d -m 0700 "$jobs_root"
    exec 9>"$jobs_root/.execution.lock"
    if ! flock -n 9; then
      write_status failed
      exit 2
    fi
    write_status running
    rm -f -- "$result_tmp"
    evidence_command="kepler-collision-${resource}-evidence"
    if "$evidence_command" "$mode" "$inventory_sha" "$container_id" >"$result_tmp" 2>/dev/null \
      && python3 - "$result_tmp" "$inventory_sha" "$container_id" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1]))
if result.get("inventory_sha256") != sys.argv[2] or result.get("source_container_id") != sys.argv[3]:
    raise SystemExit(2)
PY
    then
      chmod 0600 "$result_tmp"
      mv "$result_tmp" "$result_file"
      write_status passed
    else
      exit_code=$?
      rm -f -- "$result_tmp" "$result_file"
      write_status failed
      exit "$exit_code"
    fi
    ;;
  status)
    if [[ -f $status_file ]]; then
      cat "$status_file"
    else
      printf '{"request_sha256":"%s","state":"missing"}\n' "$request_sha"
    fi
    ;;
  result)
    if [[ ! -f $status_file || ! -f $result_file ]] || ! grep -Fqx \
      "{\"request_sha256\":\"$request_sha\",\"state\":\"passed\"}" "$status_file"; then
      echo "evidence job halted: result unavailable" >&2
      exit 2
    fi
    cat "$result_file"
    ;;
  *) usage ;;
esac
