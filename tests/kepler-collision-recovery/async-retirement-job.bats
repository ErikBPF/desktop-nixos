#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export MANIFEST_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export INVENTORY_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export KEPLER_RECOVERY_TEST_ROOT="$BATS_TEST_TMPDIR/fast/backups/kepler-collision-k1"
  export MOCK_LOG="$BATS_TEST_TMPDIR/commands.log"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export MANIFEST="$BATS_TEST_TMPDIR/manifest.json"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '{"manifest":{},"manifest_sha256":"%s"}\n' "$MANIFEST_SHA" >"$MANIFEST"
  cat >"$BATS_TEST_TMPDIR/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$MOCK_LOG"
printf '\n' >>"$MOCK_LOG"
SH
  cat >"$BATS_TEST_TMPDIR/bin/kepler-collision-recovery-executor" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"$MOCK_LOG"
printf '\n' >>"$MOCK_LOG"
if [[ " $* " == *" --execute "* ]]; then
  printf 'DONE database airflow\nDONE path /bulk/git\n'
else
  printf 'DRY-RUN database airflow\nDRY-RUN path /bulk/git\n'
fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

job() {
  bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_retirement_job.sh" "$@"
}

@test "submit validates then dispatches declared user unit asynchronously" {
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$INVENTORY_SHA"
  [ "$status" -eq 0 ]
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  [[ $REQUEST_SHA =~ ^[0-9a-f]{64}$ ]]
  grep -F -- "--user start --no-block kepler-collision-retirement@$REQUEST_SHA.service" "$MOCK_LOG"
  [ "$(stat -c %a "$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA/request.json")" = 600 ]
  [ "$(stat -c %a "$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA/manifest.json")" = 600 ]
  [ "$(stat -c %a "$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA")" = 700 ]
}

@test "identical submit is idempotent and conflicting active submit is rejected" {
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$INVENTORY_SHA"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$INVENTORY_SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\"request_sha256\":\"$REQUEST_SHA\""* ]]
  [ "$(grep -c -- '--user start --no-block' "$MOCK_LOG")" -eq 1 ]

  other=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$other"
  [ "$status" -eq 2 ]
  [[ "$output" == *'different request active'* ]]
}

@test "execute publishes atomic value-free result for reconnect polling" {
  export SECRET_VALUE=must-not-escape
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$INVENTORY_SHA"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  run job execute "$REQUEST_SHA"
  [ "$status" -eq 0 ]
  run job status "$REQUEST_SHA"
  [[ "$output" == *'"state":"passed"'* ]]
  [[ "$output" != *must-not-escape* ]]
  run job result "$REQUEST_SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"completed":["database airflow","path /bulk/git"]'* ]]
  [[ "$output" != *must-not-escape* ]]
  [ ! -e "$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA/result.json.tmp" ]
  [ "$(stat -c %a "$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA/result.json")" = 600 ]
}

@test "pending job never returns partial result" {
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$INVENTORY_SHA"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  printf '{"partial":true}\n' >"$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA/result.json.tmp"
  run job result "$REQUEST_SHA"
  [ "$status" -eq 2 ]
  [[ "$output" != *partial* ]]
}

@test "executor failure publishes no raw output or result" {
  cat >"$BATS_TEST_TMPDIR/bin/kepler-collision-recovery-executor" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" --execute "* ]]; then
  printf 'private must-not-escape\n' >&2
  exit 2
fi
printf 'DRY-RUN database airflow\n'
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/kepler-collision-recovery-executor"
  run job submit "$MANIFEST" "$MANIFEST_SHA" "$INVENTORY_SHA"
  REQUEST_SHA=$(printf '%s' "$output" | jq -r .request_sha256)
  run job execute "$REQUEST_SHA"
  [ "$status" -eq 2 ]
  [[ "$output" != *must-not-escape* ]]
  run job status "$REQUEST_SHA"
  [[ "$output" == *'"reason":"executor-failed"'* ]]
  [ ! -e "$KEPLER_RECOVERY_TEST_ROOT/retirement-jobs/$REQUEST_SHA/result.json" ]
}

@test "invalid bindings halt before executor and systemd" {
  run job submit "$MANIFEST" short "$INVENTORY_SHA"
  [ "$status" -eq 2 ]
  [ ! -e "$MOCK_LOG" ]
}
