#!/usr/bin/env bats
# Each Bats test intentionally has isolated exports.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

setup() {
  export SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export SOURCE_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  export MOCK_ID=$SOURCE_ID
  MOCK_IMAGE_ID=sha256:$(printf '%064d' 1)
  export MOCK_IMAGE_ID
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export KEPLER_RECOVERY_TEST_ROOT="$BATS_TEST_TMPDIR/fast/backups/kepler-collision-k1"
  export MOCK_LOG="$BATS_TEST_TMPDIR/podman.log"
  export MOCK_STATE=running
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat >"$BATS_TEST_TMPDIR/bin/podman" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$MOCK_LOG"
printf '\n' >>"$MOCK_LOG"
case " $* " in
  *" inspect --format {{.State.Status}} "*) printf '%s\n' "$MOCK_STATE" ;;
  *" inspect --format {{.Id}} "*) printf '%s\n' "$MOCK_ID" ;;
  *" inspect --format {{.Image}} "*) printf '%s\n' "$MOCK_IMAGE_ID" ;;
  *" pg_get_userbyid"*) printf 'airflow|airflow\napp|app_owner\npostgres|postgres\n' ;;
  *" exec "*" pg_dump "*) printf '%s\n' 'CREATE TABLE retained(id integer);' ;;
  *" exec "*" psql "*) cat >/dev/null ;;
  *" exec redis "*"redis-cli SAVE"*) ;;
  *" exec redis "*"DBSIZE"*) printf '2\n' ;;
  *" exec redis "*"redis-cli --scan"*) printf '%064d\n' 7 ;;
  *" exec kepler-k1-redis-restore-"*"DBSIZE"*) printf '2\n' ;;
  *" exec kepler-k1-redis-restore-"*"redis-cli --scan"*) printf '%064d\n' 7 ;;
  *" cp redis:/data/dump.rdb "*)
    destination=${@: -1}; mkdir -p "$(dirname "$destination")"; printf redis-fixture >"$destination"
    ;;
  *) ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/podman" "$BATS_TEST_TMPDIR/bin/sleep"
}

@test "PostgreSQL backup and isolated restore emit metadata only" {
  export POSTGRES_PASSWORD=must-not-escape
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_postgres_evidence.sh" run "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"schema":"kepler-collision-database-evidence-v2"'* ]]
  [[ "$output" == *'"cluster_restore"'*'"status":"passed"'* ]]
  [[ "$output" == *'"database_inventory"'* ]]
  [[ "$output" == *'"retained_databases":[{"name":"app","owner":"app_owner"},{"name":"postgres","owner":"postgres"}]'* ]]
  [[ "$output" == *'"retired_databases":["airflow"]'* ]]
  [[ "$output" != *must-not-escape* ]]
  [ -f "$KEPLER_RECOVERY_TEST_ROOT/postgres/$SHA/retained-databases.tar" ]
  grep -F -- "--network none --name kepler-k1-postgres-restore-aaaaaaaaaaaa" "$MOCK_LOG"
  run ! grep -E 'prune|system reset|rm --all' "$MOCK_LOG"
}

@test "Redis SAVE backup and isolated restore emit hashes not credentials" {
  export REDIS_PASSWORD=must-not-escape
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_redis_evidence.sh" run "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"resource":"redis"'* ]]
  [[ "$output" == *'"logical_sha256"'* ]]
  [[ "$output" == *'"key_count":2'* ]]
  [[ "$output" != *must-not-escape* ]]
  [ -f "$KEPLER_RECOVERY_TEST_ROOT/redis/$SHA/dump.rdb" ]
  grep -F -- "--network none --name kepler-k1-redis-restore-aaaaaaaaaaaa" "$MOCK_LOG"
  grep -F -- "volume rm kepler-k1-redis-restore-aaaaaaaaaaaa-data" "$MOCK_LOG"
  run ! grep -E 'prune|system reset|volume rm --all' "$MOCK_LOG"
}

@test "invalid inventory binding halts before Podman" {
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_postgres_evidence.sh" run short "$SOURCE_ID"
  [ "$status" -eq 2 ]
  [ ! -e "$MOCK_LOG" ]
}

@test "non-running exact source halts without creating restore resource" {
  export MOCK_STATE=exited
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_redis_evidence.sh" run "$SHA" "$SOURCE_ID"
  [ "$status" -eq 2 ]
  run ! grep -E ' create | volume create ' "$MOCK_LOG"
}

@test "source container ID drift halts before action" {
  export MOCK_ID=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_postgres_evidence.sh" run "$SHA" "$SOURCE_ID"
  [ "$status" -eq 2 ]
  grep -F -- "inspect --format \{\{.Id\}\} postgres" "$MOCK_LOG"
  run ! grep -E ' exec | create | start | stop ' "$MOCK_LOG"
}

@test "run-stopped starts and always stops exact source ID" {
  export MOCK_STATE=exited
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_redis_evidence.sh" run-stopped "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  grep -F -- "start $SOURCE_ID" "$MOCK_LOG"
  grep -F -- "stop $SOURCE_ID" "$MOCK_LOG"
}

@test "Podman bare immutable image ID is accepted for disposable restore" {
  MOCK_IMAGE_ID=$(printf '%064d' 1)
  export MOCK_IMAGE_ID
  run bash "$REPO_ROOT/modules/hosts/kepler/_collision_recovery_postgres_evidence.sh" run "$SHA" "$SOURCE_ID"
  [ "$status" -eq 0 ]
  grep -F -- "$MOCK_IMAGE_ID" "$MOCK_LOG"
}
