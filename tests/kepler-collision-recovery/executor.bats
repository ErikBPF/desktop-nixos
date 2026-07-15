#!/usr/bin/env bats

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/root"
  export MOCK_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/fast/apps/gitlab/config"
  : >"$MOCK_LOG"
  for command in podman dropdb rm ssh; do
    cat >"$TEST_ROOT/bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$(basename "$0")" >>"$MOCK_LOG"
printf ' <%s>' "$@" >>"$MOCK_LOG"
printf '\n' >>"$MOCK_LOG"
EOF
    chmod +x "$TEST_ROOT/bin/$command"
  done
  cat >"$TEST_ROOT/bin/podman" <<'EOF'
#!/usr/bin/env bash
printf 'podman' >>"$MOCK_LOG"
printf ' <%s>' "$@" >>"$MOCK_LOG"
printf '\n' >>"$MOCK_LOG"
if [[ $1 == inspect ]]; then printf 'false\n'; fi
EOF
  chmod +x "$TEST_ROOT/bin/podman"
  export PATH="$TEST_ROOT/bin:$PATH"
  export POSTGRES_USER="actual-user"
  export EXECUTOR="$BATS_TEST_DIRNAME/../../modules/hosts/kepler/_collision_recovery_executor.sh"
  export MANIFEST="$BATS_TEST_TMPDIR/manifest.json"
  python3 - "$MANIFEST" <<'PY'
import hashlib, json, sys
manifest = {
  "schema": "kepler-retirement-approval-manifest-v1",
  "inventory_sha256": "a" * 64,
  "actions": [
    {"kind":"container", "resource":"gitlab", "command":["just","kepler-recovery-retire-exact","container","1"*64]},
    {"kind":"volume", "resource":"airflow_airflow_logs", "command":["just","kepler-recovery-retire-exact","volume","airflow_airflow_logs"]},
    {"kind":"volume", "resource":"orchestration_restate_data", "command":["just","kepler-recovery-retire-exact","volume","orchestration_restate_data"]},
    {"kind":"path", "resource":"/fast/apps/gitlab/config", "command":["just","kepler-recovery-retire-exact","path","/fast/apps/gitlab/config"]},
    {"kind":"artifact", "resource":"/fast/ai-models/f5-tts", "command":["just","kepler-recovery-retire-exact","artifact","/fast/ai-models/f5-tts"]},
    {"kind":"image", "resource":"sha256:"+"2"*64, "command":["just","kepler-recovery-retire-exact","image","sha256:"+"2"*64]},
    {"kind":"database", "resource":"airflow", "command":["just","kepler-recovery-retire-exact","database","airflow"], "guard":{"container_id":"3"*64,"container_name":"postgres"}},
  ],
  "execution": "unsupported-by-this-planner",
}
canonical = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
wrapper = {"manifest": manifest, "manifest_sha256": hashlib.sha256(canonical).hexdigest()}
json.dump(wrapper, open(sys.argv[1], "w"), sort_keys=True, separators=(",", ":"))
PY
  SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$MANIFEST")"
  export SHA
}

@test "defaults to dry-run and executes nothing" {
  run "$EXECUTOR" --manifest "$MANIFEST" --manifest-sha256 "$SHA" --inventory-sha256 "$(printf 'a%.0s' {1..64})"
  [ "$status" -eq 0 ]
  [ ! -s "$MOCK_LOG" ]
  [[ "$output" == *"DRY-RUN container"* ]]
  [[ "$output" != *"environment"* ]]
}

@test "execute requires both exact bindings" {
  run "$EXECUTOR" --execute --manifest "$MANIFEST" --manifest-sha256 "$SHA"
  [ "$status" -ne 0 ]
  [ ! -s "$MOCK_LOG" ]
  run "$EXECUTOR" --execute --manifest "$MANIFEST" --manifest-sha256 "$(printf 'f%.0s' {1..64})" --inventory-sha256 "$(printf 'a%.0s' {1..64})"
  [ "$status" -ne 0 ]
  [ ! -s "$MOCK_LOG" ]
}

@test "execute dispatches only exact resources without values" {
  run "$EXECUTOR" --execute --manifest "$MANIFEST" --manifest-sha256 "$SHA" --inventory-sha256 "$(printf 'a%.0s' {1..64})"
  [ "$status" -eq 0 ]
  run grep -E '^ssh ' "$MOCK_LOG"
  [ "$status" -eq 1 ]
  run grep -Ex 'podman <rm> <--force> <1{64}>' "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx "podman <volume> <rm> <airflow_airflow_logs>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx "podman <volume> <rm> <orchestration_restate_data>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx "rm <--one-file-system> <--recursive> <--force> <--> </fast/apps/gitlab/config>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx "rm <--one-file-system> <--recursive> <--force> <--> </fast/ai-models/f5-tts>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx "podman <image> <rm> <sha256:$(printf '2%.0s' {1..64})>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2016
  run grep -Fx "podman <start> <$(printf '3%.0s' {1..64})>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx 'podman <exec> <3333333333333333333333333333333333333333333333333333333333333333> <sh> <-ceu> <exec pg_isready -U "$POSTGRES_USER" -d postgres>' "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx 'podman <exec> <3333333333333333333333333333333333333333333333333333333333333333> <sh> <-ceu> <exec dropdb --if-exists -U "$POSTGRES_USER" airflow>' "$MOCK_LOG"
  [ "$status" -eq 0 ]
  run grep -Fx "podman <stop> <$(printf '3%.0s' {1..64})>" "$MOCK_LOG"
  [ "$status" -eq 0 ]
  [[ "$(<"$MOCK_LOG")" != *"actual-user"* ]]
}

@test "accepts only the exact F5 artifact root" {
  for target in /fast/ai-models/f5-tts/checkpoint /fast/ai-models/refs; do
    python3 - "$MANIFEST" "$target" <<'PY'
import hashlib,json,sys
w=json.load(open(sys.argv[1])); target=sys.argv[2]
w["manifest"]["actions"]=[{"kind":"artifact","resource":target,"command":["just","kepler-recovery-retire-exact","artifact",target]}]
w["manifest_sha256"]=hashlib.sha256((json.dumps(w["manifest"],sort_keys=True,separators=(",",":"))+"\n").encode()).hexdigest()
json.dump(w,open(sys.argv[1],"w"),sort_keys=True,separators=(",",":"))
PY
    SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$MANIFEST")"
    run "$EXECUTOR" --execute --manifest "$MANIFEST" --manifest-sha256 "$SHA" --inventory-sha256 "$(printf 'a%.0s' {1..64})"
    [ "$status" -ne 0 ]
    [ ! -s "$MOCK_LOG" ]
  done
}

@test "preflight rejects unsafe action before any command" {
  python3 - "$MANIFEST" <<'PY'
import hashlib, json, sys
w=json.load(open(sys.argv[1])); w["manifest"]["actions"][2]["resource"]="/fast/apps"
w["manifest_sha256"]=hashlib.sha256((json.dumps(w["manifest"],sort_keys=True,separators=(",",":"))+"\n").encode()).hexdigest()
json.dump(w,open(sys.argv[1],"w"),sort_keys=True,separators=(",",":"))
PY
  SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$MANIFEST")"
  run "$EXECUTOR" --execute --manifest "$MANIFEST" --manifest-sha256 "$SHA" --inventory-sha256 "$(printf 'a%.0s' {1..64})"
  [ "$status" -ne 0 ]
  [ ! -s "$MOCK_LOG" ]
}

@test "rejects prune secret and unknown operations" {
  for kind in prune secret snapshot; do
    python3 - "$MANIFEST" "$kind" <<'PY'
import hashlib,json,sys
w=json.load(open(sys.argv[1])); w["manifest"]["actions"]=[{"kind":sys.argv[2],"resource":"x","command":["prune"]}]
w["manifest_sha256"]=hashlib.sha256((json.dumps(w["manifest"],sort_keys=True,separators=(",",":"))+"\n").encode()).hexdigest()
json.dump(w,open(sys.argv[1],"w"),sort_keys=True,separators=(",",":"))
PY
    SHA="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$MANIFEST")"
    run "$EXECUTOR" --execute --manifest "$MANIFEST" --manifest-sha256 "$SHA" --inventory-sha256 "$(printf 'a%.0s' {1..64})"
    [ "$status" -ne 0 ]
    [ ! -s "$MOCK_LOG" ]
  done
}
