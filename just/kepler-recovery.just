# Collect sanitized K1 collision evidence. Collector executes from committed
# stdin, writes nothing remotely, and emits only allowlisted runtime metadata.
kepler-recovery-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    collector="modules/hosts/kepler/_collision_recovery_inventory.py"
    remote_sanitizer="modules/hosts/kepler/_collision_recovery_remote.sh"
    evidence_dir=".gsd/evidence/kepler-k1"
    out="$evidence_dir/inventory.json"
    test -f "$collector" -a -f "$remote_sanitizer"
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tmp="$(mktemp "$evidence_dir/.inventory.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} 'bash -s' < "$remote_sanitizer" \
      | python3 "$collector" --remote-input > "$tmp"
    python3 - "$tmp" <<'PY'
    import hashlib
    import json
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    result = json.loads(path.read_text())
    inventory = result["inventory"]
    canonical = (json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()
    actual = hashlib.sha256(canonical).hexdigest()
    if result.get("schema") != "kepler-collision-inventory-v1" or result.get("inventory_sha256") != actual:
        raise SystemExit("inventory envelope/hash validation failed")
    PY
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'inventory=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["inventory_sha256"])' "$out")"

# Probe only reviewed retirement paths. The helper emits metadata, never
# directory listings, contents, environment, or content-derived hashes.
kepler-recovery-retirement-paths:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    helper="modules/hosts/kepler/_collision_recovery_retirement_paths_remote.py"
    evidence_dir=".gsd/evidence/kepler-k1"
    out="$evidence_dir/retirement-paths.json"
    test -f "$helper"
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tmp="$(mktemp "$evidence_dir/.retirement-paths.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} \
      'tool=$(command -v kepler-collision-recovery-inventory); interpreter=$(head -n1 "$tool"); interpreter=${interpreter#\#!}; exec "$interpreter" -' \
      < "$helper" > "$tmp"
    python3 - "$tmp" <<'PY'
    import hashlib
    import json
    import pathlib
    import sys

    result = json.loads(pathlib.Path(sys.argv[1]).read_text())
    evidence = result.get("evidence")
    canonical = (json.dumps(evidence, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if (
        result.get("schema") != "kepler-retirement-path-evidence-envelope-v1"
        or result.get("status") != "verified"
        or not isinstance(evidence, list)
        or result.get("evidence_sha256") != hashlib.sha256(canonical).hexdigest()
    ):
        raise SystemExit("retirement path evidence envelope/hash validation failed")
    PY
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'retirement_paths=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["evidence_sha256"])' "$out")"

# Render only the separately-approved stop plan. This recipe never stops a service.
kepler-recovery-quiesce-plan inventory_sha256:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    evidence_dir=".gsd/evidence/kepler-k1"
    inventory="$evidence_dir/inventory.json"
    desired="$evidence_dir/desired.json"
    out="$evidence_dir/quiesce-manifest.json"
    python3 modules/hosts/kepler/_collision_recovery_desired.py \
      --servarr-root references/repos/servarr/machines/kepler > "$desired"
    python3 modules/hosts/kepler/_collision_recovery_quiesce.py \
      --inventory "$inventory" --desired "$desired" \
      --expected-inventory-sha256 "{{inventory_sha256}}" > "$out"
    chmod 600 "$desired" "$out"
    printf 'quiesce_manifest=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$out")"

# Produce restore-tested PostgreSQL evidence, bound to fresh inventory and ID.
kepler-recovery-postgres-evidence-run inventory_sha256 container_id mode="run-stopped":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    case "{{mode}}" in run|run-stopped) ;; *) echo "invalid evidence mode" >&2; exit 2 ;; esac
    python3 - "{{inventory_sha256}}" "{{container_id}}" <<'PY'
    import json, pathlib, sys
    inventory = json.loads(pathlib.Path(".gsd/evidence/kepler-k1/inventory.json").read_text())
    expected_sha, expected_id = sys.argv[1:]
    records = [item for item in inventory["inventory"]["containers"] if item.get("name") == "postgres"]
    if inventory.get("inventory_sha256") != expected_sha or len(records) != 1 or records[0].get("id") != expected_id:
        raise SystemExit("PostgreSQL inventory binding mismatch")
    PY
    out=".gsd/evidence/kepler-k1/database-evidence.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.database-evidence.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    submission="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job \
      submit postgres "{{mode}}" "{{inventory_sha256}}" "{{container_id}}")"
    request_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["request_sha256"])' "$submission")"
    [[ $request_sha =~ ^[0-9a-f]{64}$ ]] || { echo "invalid PostgreSQL evidence request" >&2; exit 2; }
    for _ in $(seq 1 180); do
      if ! status="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job status "$request_sha")"; then
        sleep 5
        continue
      fi
      state="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["state"])' "$status")"
      case "$state" in
        passed)
          ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job result "$request_sha" > "$tmp" && break
          ;;
        failed)
          reason="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("reason", "unspecified"))' "$status")"
          echo "PostgreSQL evidence job failed: $reason" >&2
          exit 2
          ;;
        pending|running) ;;
        *) echo "invalid PostgreSQL evidence job state" >&2; exit 2 ;;
      esac
      sleep 5
    done
    [[ -s $tmp ]] || { echo "PostgreSQL evidence job timed out; remote job was not stopped" >&2; exit 2; }
    python3 -m json.tool "$tmp" >/dev/null
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'database_evidence=%s\n' "$out"

# Produce restore-tested Redis evidence, bound to the fresh inventory and ID.
kepler-recovery-redis-evidence-run inventory_sha256 container_id mode="run-stopped":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    case "{{mode}}" in run|run-stopped) ;; *) echo "invalid evidence mode" >&2; exit 2 ;; esac
    python3 - "{{inventory_sha256}}" "{{container_id}}" <<'PY'
    import json, pathlib, sys
    inventory = json.loads(pathlib.Path(".gsd/evidence/kepler-k1/inventory.json").read_text())
    expected_sha, expected_id = sys.argv[1:]
    records = [item for item in inventory["inventory"]["containers"] if item.get("name") == "redis"]
    if inventory.get("inventory_sha256") != expected_sha or len(records) != 1 or records[0].get("id") != expected_id:
        raise SystemExit("Redis inventory binding mismatch")
    PY
    out=".gsd/evidence/kepler-k1/redis-evidence.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.redis-evidence.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    submission="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job \
      submit redis "{{mode}}" "{{inventory_sha256}}" "{{container_id}}")"
    request_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["request_sha256"])' "$submission")"
    [[ $request_sha =~ ^[0-9a-f]{64}$ ]] || { echo "invalid Redis evidence request" >&2; exit 2; }
    for _ in $(seq 1 180); do
      if ! status="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job status "$request_sha")"; then
        sleep 5
        continue
      fi
      state="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["state"])' "$status")"
      case "$state" in
        passed)
          ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job result "$request_sha" > "$tmp" && break
          ;;
        failed)
          reason="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("reason", "unspecified"))' "$status")"
          echo "Redis evidence job failed: $reason" >&2
          exit 2
          ;;
        pending|running) ;;
        *) echo "invalid Redis evidence job state" >&2; exit 2 ;;
      esac
      sleep 5
    done
    [[ -s $tmp ]] || { echo "Redis evidence job timed out; remote job was not stopped" >&2; exit 2; }
    python3 -m json.tool "$tmp" >/dev/null
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'redis_evidence=%s\n' "$out"

# Validate value-free retained PostgreSQL backup/restore evidence locally.
kepler-recovery-postgres-evidence-plan inventory_sha256 evidence=".gsd/evidence/kepler-k1/database-evidence.json":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    out=".gsd/evidence/kepler-k1/database-manifest.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.database-manifest.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/kepler/_collision_recovery_database_evidence.py \
      --inventory .gsd/evidence/kepler-k1/inventory.json \
      --evidence "{{evidence}}" \
      --expected-inventory-sha256 "{{inventory_sha256}}" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'database_manifest=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$out")"

# Render the exact Redis backup/restore plan; never executes its actions.
kepler-recovery-redis-backup-plan inventory_sha256 approval="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(
      --inventory .gsd/evidence/kepler-k1/inventory.json
      --expected-inventory-sha256 "{{inventory_sha256}}"
    )
    if [ -n "{{approval}}" ]; then args+=(--quiesce-approval "{{approval}}"); fi
    python3 modules/hosts/kepler/_collision_recovery_redis_backup.py "${args[@]}"

# Assemble value-free retirement evidence from authenticated live envelopes.
kepler-recovery-retirement-evidence:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    out=".gsd/evidence/kepler-k1/retirement-evidence.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.retirement-evidence.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    args=(
      --inventory .gsd/evidence/kepler-k1/inventory.json
      --retirement-paths .gsd/evidence/kepler-k1/retirement-paths.json
      --database-evidence .gsd/evidence/kepler-k1/database-manifest.json
    )
    if [ -f .gsd/evidence/kepler-k1/redis-evidence.json ]; then
      args+=(--redis-evidence .gsd/evidence/kepler-k1/redis-evidence.json)
    fi
    python3 modules/hosts/kepler/_collision_recovery_retirement_evidence.py "${args[@]}" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'retirement_evidence=%s\n' "$out"

# Render the exact retirement/disposition manifest from reviewed evidence.
kepler-recovery-retirement-plan evidence=".gsd/evidence/kepler-k1/retirement-evidence.json":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    out=".gsd/evidence/kepler-k1/retirement-manifest.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.retirement-manifest.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/kepler/_collision_recovery_retirement.py \
      .gsd/evidence/kepler-k1/inventory.json "{{evidence}}" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'retirement_manifest=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$out")"

# Execute one reviewed retirement manifest after a fresh inventory hash match.
kepler-recovery-retirement-remote-verify manifest_sha256 inventory_sha256 manifest=".gsd/evidence/kepler-k1/retirement-manifest.json":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{manifest_sha256}}" =~ ^[0-9a-f]{64}$ && "{{inventory_sha256}}" =~ ^[0-9a-f]{64}$ ]] || {
      echo "invalid retirement binding" >&2
      exit 2
    }
    python3 - "{{manifest}}" "{{manifest_sha256}}" <<'PY'
    import json, pathlib, sys
    wrapper = json.loads(pathlib.Path(sys.argv[1]).read_text())
    if wrapper.get("manifest_sha256") != sys.argv[2]:
        raise SystemExit("retirement manifest SHA-256 mismatch")
    PY
    ssh -p 2222 erik@{{ip_kepler}} \
      'tmp=$(mktemp); trap '\''rm -f "$tmp"'\'' EXIT; cat >"$tmp"; kepler-collision-recovery-executor --manifest "$tmp" --manifest-sha256 "{{manifest_sha256}}" --inventory-sha256 "{{inventory_sha256}}"' \
      < "{{manifest}}"

# Execute one reviewed retirement manifest after a fresh inventory hash match.
kepler-recovery-retirement-execute manifest_sha256 inventory_sha256 manifest=".gsd/evidence/kepler-k1/retirement-manifest.json":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{manifest_sha256}}" =~ ^[0-9a-f]{64}$ && "{{inventory_sha256}}" =~ ^[0-9a-f]{64}$ ]] || {
      echo "invalid retirement binding" >&2
      exit 2
    }
    just kepler-recovery-inventory
    actual="$(python3 -c 'import json; print(json.load(open(".gsd/evidence/kepler-k1/inventory.json"))["inventory_sha256"])')"
    test "$actual" = "{{inventory_sha256}}" || { echo "retirement inventory drift" >&2; exit 2; }
    python3 - "{{manifest}}" "{{manifest_sha256}}" <<'PY'
    import json, pathlib, sys
    wrapper = json.loads(pathlib.Path(sys.argv[1]).read_text())
    if wrapper.get("manifest_sha256") != sys.argv[2]:
        raise SystemExit("retirement manifest SHA-256 mismatch")
    PY
    ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
    submission="$(ssh "${ssh_opts[@]}" erik@{{ip_kepler}} \
      'tmp=$(mktemp); trap '\''rm -f "$tmp"'\'' EXIT; cat >"$tmp"; kepler-collision-retirement-job submit "$tmp" "{{manifest_sha256}}" "{{inventory_sha256}}"' \
      < "{{manifest}}")"
    request_sha="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["request_sha256"])' <<<"$submission")"
    [[ "$request_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid retirement request binding" >&2; exit 2; }
    for _ in $(seq 1 120); do
      if status="$(ssh "${ssh_opts[@]}" erik@{{ip_kepler}} kepler-collision-retirement-job status "$request_sha")"; then
        state="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["state"])' <<<"$status")"
        case "$state" in
          passed)
            ssh "${ssh_opts[@]}" erik@{{ip_kepler}} kepler-collision-retirement-job result "$request_sha"
            exit 0
            ;;
          failed) echo "retirement job failed: $request_sha" >&2; exit 2 ;;
          pending|running) ;;
          *) echo "invalid retirement job state" >&2; exit 2 ;;
        esac
      fi
      sleep 5
    done
    echo "retirement job still remote: $request_sha" >&2
    exit 2

# Emergency exact retirement approved interactively; bypasses recovery evidence gates.
kepler-recovery-retirement-force-approved:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=10)
    host=erik@{{ip_kepler}}
    ssh "${ssh_opts[@]}" "$host" podman rm --force d4889db4a5883077f83f4236202f4294c8a2f6a492c36e7a1ffd45fd3c72bb87 2>/dev/null || true
    echo 'DONE container ha-train-run'
    ssh "${ssh_opts[@]}" "$host" podman rm --force 0916806c278662045d04b7f5a470c040b9b14dd6d6c5d022045c48b8e3e5423b 2>/dev/null || true
    echo 'DONE container minicpm-train'
    ssh "${ssh_opts[@]}" "$host" podman rm --force 8e61022a6b55484a9661aabb8be7c5d782e8fc2cdaee4c0963c7bb1015d32619 2>/dev/null || true
    echo 'DONE container uv_build'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /bulk/git
    echo 'DONE path /bulk/git'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/apps/gitlab/config
    echo 'DONE path /fast/apps/gitlab/config'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/apps/gitlab/logs
    echo 'DONE path /fast/apps/gitlab/logs'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/apps/gitlab-runner
    echo 'DONE path /fast/apps/gitlab-runner'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/ai-models/f5-tts
    echo 'DONE artifact /fast/ai-models/f5-tts'
    ssh "${ssh_opts[@]}" "$host" podman image rm sha256:9a607634ac682f35bc1cd88bd7453bda11e9fdc5eb99afea3b23311d5e6f1a34 2>/dev/null || true
    echo 'DONE image gitlab'
    ssh "${ssh_opts[@]}" "$host" podman image rm sha256:3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b 2>/dev/null || true
    echo 'DONE image f5-tts'
    postgres=0146cb4f3b498654e247fca160fee2e1acfbe301d12b9a8285996a250f2686f9
    ssh "${ssh_opts[@]}" "$host" podman start "$postgres" >/dev/null
    sleep 15
    ssh "${ssh_opts[@]}" "$host" "podman exec '$postgres' sh -ceu 'exec dropdb --if-exists -U \"\$POSTGRES_USER\" airflow'"
    ssh "${ssh_opts[@]}" "$host" podman stop "$postgres" >/dev/null
    echo 'DONE database airflow'

# Exact full-container recreation approved for the Kepler recovery campaign.
kepler-recovery-reset-declared-approved:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=10)
    host=erik@{{ip_kepler}}
    containers=(
      0146cb4f3b498654e247fca160fee2e1acfbe301d12b9a8285996a250f2686f9
      ad3d3c02a8ea82090218d2e7e889a0b7c90410913ff65cc30f9f5d1db19bb434
      1088499c85881d0cd34c4bfd33174ff60cdc7af5425c5d0b35c596ece084f060
      306ee7200b6e0ccf8f7256bcd6e8d9fcf1032a6c91389ab727459506200ae728
      70af9b17b63a2eecb57ac1411440db631d21880e73718b6b00cd4f198f44f832
      84f32d8fe1b01e7f7be30cbe01034c80e95f689a1cff6e2437f22c8e24a9accc
      e055b76f6587be195f6fe5f2e455ed9d3115cbac6826fd0084b2a5703403abf1
      f9ee1a9901d5b3870d85218a64d112bbe9752542093e6dcd2241347f693acc2f
      a90e47f940e0ec80b8ac37be028064cd1d1db4fcc2705674b035f2920c42e4c3
      9314084a100d410926e5a6c9e1e6cf373fcfdcc88db5d7e4e85e3a76d2483462
      f28fdf964e96b0117f021ec73c1e028a0fd3116a92a960b70e515f58d55bec1c
      f9a131792be86483d3d950599192c4d717f0d8b366b469773534a67f8e5f6e8e
    )
    for id in "${containers[@]}"; do
      ssh "${ssh_opts[@]}" "$host" podman rm --force "$id"
      echo "DONE container $id"
    done
    ssh "${ssh_opts[@]}" "$host" podman volume rm homelab_redis_data
    echo 'DONE volume homelab_redis_data'
    ssh "${ssh_opts[@]}" "$host" podman volume rm infra_redis_data
    echo 'DONE volume infra_redis_data'
