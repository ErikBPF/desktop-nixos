# shellcheck shell=bash
set -euo pipefail

usage() {
  echo "usage: kepler-collision-retirement-job submit MANIFEST MANIFEST_SHA256 INVENTORY_SHA256 | execute|status|result REQUEST_SHA256" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
operation=$1
backup_base=/fast/backups/kepler-collision-k1
if [[ -n ${KEPLER_RECOVERY_TEST_ROOT:-} ]]; then
  [[ -n ${BATS_TEST_TMPDIR:-} && $KEPLER_RECOVERY_TEST_ROOT == "$BATS_TEST_TMPDIR"/* ]] || {
    echo "retirement job halted: invalid test root" >&2
    exit 2
  }
  backup_base=$KEPLER_RECOVERY_TEST_ROOT
fi
jobs_root="$backup_base/retirement-jobs"
active_file="$jobs_root/active"
umask 077

write_status() {
  local state=$1 reason=${2:-}
  if [[ -n $reason ]]; then
    printf '{"reason":"%s","request_sha256":"%s","state":"%s"}\n' "$reason" "$request_sha" "$state" >"$status_file.tmp"
  else
    printf '{"request_sha256":"%s","state":"%s"}\n' "$request_sha" "$state" >"$status_file.tmp"
  fi
  chmod 0600 "$status_file.tmp"
  mv "$status_file.tmp" "$status_file"
}

if [[ $operation == submit ]]; then
  [[ $# -eq 4 ]] || usage
  source_manifest=$2
  manifest_sha=$3
  inventory_sha=$4
  [[ -r $source_manifest ]] || {
    echo "retirement job halted: readable manifest required" >&2
    exit 2
  }
  [[ $manifest_sha =~ ^[0-9a-f]{64}$ && $inventory_sha =~ ^[0-9a-f]{64}$ ]] || usage

  # Reuse the executor's complete manifest validation without mutation.
  kepler-collision-recovery-executor \
    --manifest "$source_manifest" \
    --manifest-sha256 "$manifest_sha" \
    --inventory-sha256 "$inventory_sha" >/dev/null 2>&1 || {
    echo "retirement job halted: manifest preflight failed" >&2
    exit 2
  }

  request=$(python3 - "$manifest_sha" "$inventory_sha" <<'PY'
import json
import sys

manifest_sha, inventory_sha = sys.argv[1:]
print(json.dumps({
    "inventory_sha256": inventory_sha,
    "manifest_sha256": manifest_sha,
    "schema": "kepler-collision-retirement-request-v1",
}, sort_keys=True, separators=(",", ":")))
PY
  )
  request_sha=$(printf '%s\n' "$request" | sha256sum | cut -d' ' -f1)
  root="$jobs_root/$request_sha"
  request_file="$root/request.json"
  manifest_file="$root/manifest.json"
  status_file="$root/status.json"
  install -d -m 0700 "$jobs_root" "$root"
  exec 8>"$jobs_root/.submit.lock"
  flock 8

  if [[ -f $active_file ]]; then
    active=$(<"$active_file")
    active_status="$jobs_root/$active/status.json"
    if [[ $active != "$request_sha" && -f $active_status ]] \
      && grep -Eq '"state":"(pending|running)"' "$active_status"; then
      echo "retirement job halted: different request active" >&2
      exit 2
    fi
  fi
  if [[ -f $request_file ]] && [[ $(sha256sum "$request_file" | cut -d' ' -f1) != "$request_sha" ]]; then
    echo "retirement job halted: request collision" >&2
    exit 2
  fi
  if [[ -f $manifest_file ]] && ! cmp -s -- "$source_manifest" "$manifest_file"; then
    echo "retirement job halted: manifest collision" >&2
    exit 2
  fi
  if [[ ! -f $request_file ]]; then
    printf '%s\n' "$request" >"$request_file.tmp"
    chmod 0600 "$request_file.tmp"
    mv "$request_file.tmp" "$request_file"
  fi
  if [[ ! -f $manifest_file ]]; then
    cp -- "$source_manifest" "$manifest_file.tmp"
    chmod 0600 "$manifest_file.tmp"
    mv "$manifest_file.tmp" "$manifest_file"
  fi
  if [[ -f $status_file ]] && grep -Eq '"state":"(pending|running|passed)"' "$status_file"; then
    state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$status_file")
    printf '{"request_sha256":"%s","state":"%s"}\n' "$request_sha" "$state"
    exit 0
  fi
  printf '%s\n' "$request_sha" >"$active_file.tmp"
  chmod 0600 "$active_file.tmp"
  mv "$active_file.tmp" "$active_file"
  write_status pending
  if ! systemctl --user start --no-block "kepler-collision-retirement@$request_sha.service"; then
    write_status failed dispatch-failed
    exit 2
  fi
  printf '{"request_sha256":"%s","state":"submitted"}\n' "$request_sha"
  exit 0
fi

[[ $# -eq 2 && $2 =~ ^[0-9a-f]{64}$ ]] || usage
request_sha=$2
root="$jobs_root/$request_sha"
request_file="$root/request.json"
manifest_file="$root/manifest.json"
status_file="$root/status.json"
result_file="$root/result.json"
result_tmp="$root/result.json.tmp"

case $operation in
  execute)
    [[ -f $request_file && -f $manifest_file && $(sha256sum "$request_file" | cut -d' ' -f1) == "$request_sha" ]] || {
      echo "retirement job halted: invalid request binding" >&2
      exit 2
    }
    mapfile -t fields < <(python3 - "$request_file" <<'PY'
import json
import re
import sys

request = json.load(open(sys.argv[1]))
if set(request) != {"schema", "manifest_sha256", "inventory_sha256"}:
    raise SystemExit(2)
if request.get("schema") != "kepler-collision-retirement-request-v1":
    raise SystemExit(2)
if not all(re.fullmatch(r"[0-9a-f]{64}", request.get(key, "")) for key in ("manifest_sha256", "inventory_sha256")):
    raise SystemExit(2)
print(request["manifest_sha256"])
print(request["inventory_sha256"])
PY
    )
    [[ ${#fields[@]} -eq 2 ]] || exit 2
    manifest_sha=${fields[0]}
    inventory_sha=${fields[1]}
    install -d -m 0700 "$jobs_root"
    exec 9>"$jobs_root/.execution.lock"
    if ! flock -n 9; then
      write_status failed execution-locked
      exit 2
    fi
    write_status running
    output_tmp="$root/executor-output.tmp"
    error_tmp="$root/executor-error.tmp"
    rm -f -- "$output_tmp" "$error_tmp" "$result_tmp" "$result_file"
    if kepler-collision-recovery-executor --execute \
      --manifest "$manifest_file" \
      --manifest-sha256 "$manifest_sha" \
      --inventory-sha256 "$inventory_sha" >"$output_tmp" 2>"$error_tmp" \
      && python3 - "$output_tmp" "$request_sha" "$manifest_sha" "$inventory_sha" >"$result_tmp" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
pattern = re.compile(r"DONE (container|volume|path|artifact|image|database) ([^\t\r\n\0]+)")
completed = []
for line in lines:
    match = pattern.fullmatch(line)
    if not match:
        raise SystemExit(2)
    completed.append(f"{match.group(1)} {match.group(2)}")
if not completed:
    raise SystemExit(2)
print(json.dumps({
    "completed": completed,
    "inventory_sha256": sys.argv[4],
    "manifest_sha256": sys.argv[3],
    "output_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    "request_sha256": sys.argv[2],
    "schema": "kepler-collision-retirement-result-v1",
    "status": "passed",
}, sort_keys=True, separators=(",", ":")))
PY
    then
      rm -f -- "$output_tmp" "$error_tmp"
      chmod 0600 "$result_tmp"
      mv "$result_tmp" "$result_file"
      write_status passed
    else
      exit_code=$?
      rm -f -- "$output_tmp" "$error_tmp" "$result_tmp" "$result_file"
      write_status failed executor-failed
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
      echo "retirement job halted: result unavailable" >&2
      exit 2
    fi
    cat "$result_file"
    ;;
  *) usage ;;
esac
