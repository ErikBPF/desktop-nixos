#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export SOURCE_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export KEPLER_RECOVERY_TEST_ROOT="$BATS_TEST_TMPDIR/fast/backups/kepler-collision-k1"
  export MOCK_LOG="$BATS_TEST_TMPDIR/commands.log"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$MOCK_LOG"
printf '\n' >>"$MOCK_LOG"
SH
  cat >"$BATS_TEST_TMPDIR/bin/kepler-collision-postgres-evidence" <<'SH'
#!/usr/bin/env bash
printf '{"inventory_sha256":"%s","schema":"test-evidence","source_container_id":"%s"}\n' "$2" "$3"
SH
  cat >"$BATS_TEST_TMPDIR/bin/kepler-collision-redis-evidence" <<'SH'
#!/usr/bin/env bash
printf '{"inventory_sha256":"%s","schema":"test-evidence","source_container_id":"%s"}\n' "$2" "$3"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

@test "submit dispatches one declared user unit without waiting for SSH" {
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit postgres run-stopped "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  [[ $REQUEST_SHA =~ ^[0-9a-f]{64}$ ]]
  [[ "$output" == *'"state":"submitted"'* ]]
  grep -F -- "--user start --no-block kepler-collision-evidence@$REQUEST_SHA.service" "$MOCK_LOG"
}

@test "execute stores atomic value-free result and passed status" {
  export POSTGRES_PASSWORD=must-not-escape
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit postgres run-stopped "$SHA" "$SOURCE_ID"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" execute "$REQUEST_SHA"
  [ "$status" -eq 0 ]

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" status "$REQUEST_SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"passed"'* ]]
  [[ "$output" == *"\"request_sha256\":\"$REQUEST_SHA\""* ]]
  [[ "$output" != *must-not-escape* ]]

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" result "$REQUEST_SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"inventory_sha256":"aaaaaaaa'* ]]
  [[ "$output" != *must-not-escape* ]]
  [ ! -e "$KEPLER_RECOVERY_TEST_ROOT/jobs/$REQUEST_SHA/result.json.tmp" ]
}

@test "failed execution exposes no command output or secret value" {
  export REDIS_PASSWORD=must-not-escape
  cat >"$BATS_TEST_TMPDIR/bin/kepler-collision-redis-evidence" <<'SH'
#!/usr/bin/env bash
printf 'internal must-not-escape\n' >&2
exit 2
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/kepler-collision-redis-evidence"

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit redis run-stopped "$SHA" "$SOURCE_ID"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" execute "$REQUEST_SHA"
  [ "$status" -eq 2 ]
  [[ "$output" != *must-not-escape* ]]

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" status "$REQUEST_SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"failed"'* ]]
  [[ "$output" == *'"reason":"executor-failed"'* ]]
  [[ "$output" != *must-not-escape* ]]
  [ ! -e "$KEPLER_RECOVERY_TEST_ROOT/jobs/$REQUEST_SHA/result.json" ]
}

@test "identical submit is idempotent and does not start a second unit" {
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit postgres run-stopped "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit postgres run-stopped "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"request_sha256\":\"$REQUEST_SHA\""* ]]
  [[ "$output" == *'"state":"pending"'* ]]
  [ "$(wc -l <"$MOCK_LOG")" -eq 1 ]
}

@test "corrupt request binding halts before evidence command" {
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit postgres run-stopped "$SHA" "$SOURCE_ID"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  printf '{}\n' >"$KEPLER_RECOVERY_TEST_ROOT/jobs/$REQUEST_SHA/request.json"
  : >"$MOCK_LOG"

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" execute "$REQUEST_SHA"
  [ "$status" -eq 2 ]
  [ ! -s "$MOCK_LOG" ]
}

@test "pending job never publishes a partial result" {
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" \
    submit redis run-stopped "$SHA" "$SOURCE_ID"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  printf '{"partial":true}\n' >"$KEPLER_RECOVERY_TEST_ROOT/jobs/$REQUEST_SHA/result.json.tmp"

  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_evidence_job.sh" result "$REQUEST_SHA"
  [ "$status" -eq 2 ]
  [[ "$output" != *partial* ]]
}
