# shellcheck shell=bash
set -euo pipefail
umask 077

readonly repository=/home/erik/servarr
readonly compose_file=$repository/machines/discovery/networking.yml
readonly env_file=$repository/machines/discovery/.env
readonly vault_env=/run/vault-agent/networking.env
readonly evidence=/var/lib/stateful-stack-migrations/p1-swag
readonly ledger=$evidence/ledger.json
readonly baseline=$evidence/baseline.json
readonly result=$evidence/result.json
readonly saved_inventory=$evidence/approved-inventory.json
readonly saved_authorization=$evidence/authorization.json
readonly rollback_evidence=$evidence/rollback-evidence.txt
readonly kindle_png=$evidence/kindle.png
readonly snapshot=/home/.snapshots/stateful-stack-p1-swag
readonly archive=$evidence/swag-config.tar.zst
readonly archive_sha256=${archive}.sha256
readonly restore_target=$evidence/restore-only-after-approval
readonly attempt_02=$evidence/attempt-02
readonly attempt_02_authorization=$attempt_02/authorization.json
readonly attempt_02_kindle_png=$attempt_02/kindle.png
readonly attempt_02_observation=$attempt_02/observation.json
readonly attempt_02_post_runtime=$attempt_02/post-runtime.json
readonly attempt_02_result=$attempt_02/result.json
readonly attempt_02_phases=$attempt_02/phases
readonly init_complete=$attempt_02_phases/init-complete
readonly swag_complete=$attempt_02_phases/swag-complete
readonly validation_complete=$attempt_02_phases/validation-complete
readonly predecessor_manifest_sha=ee7861b9789f08a6fb0319ba931760054625d3e1cabe03bf43443560db3daee7
readonly predecessor_inventory_sha=35c294e9fe74e8b824df7aa8161693bfd555f09b97d1ef36b58a280d08d521e7
readonly image='lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d'
readonly image_digest='sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d'
readonly cert=/home/erik/servarr/machines/discovery/config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem
readonly dns_ini=/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini
readonly rollback_description='discovery-stateful-swag-adopt rollback --manifest-sha APPROVED_MANIFEST_SHA256'

die() {
  echo "stateful-swag-adopt: $*" >&2
  exit 1
}

usage() {
  echo 'usage: discovery-stateful-swag-adopt execute --authorization FILE --manifest-sha SHA256' >&2
  echo '       discovery-stateful-swag-adopt rollback --manifest-sha SHA256' >&2
  echo '       discovery-stateful-swag-adopt recover-pre-adoption --manifest-sha SHA256' >&2
  echo '       discovery-stateful-swag-adopt resume-attempt-02 --authorization FILE --manifest-sha SHA256' >&2
  echo '       discovery-stateful-swag-adopt observe-attempt-02' >&2
  exit 2
}

capture_resume_observation() {
  local runtime=$1 output=$2 snapshot_uuid dns_mode render_sha
  discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'post-recreate runtime capture failed'
  snapshot_uuid=$(btrfs subvolume show "$snapshot" | awk '/UUID:/ && !/Parent|Received/ {print $2; exit}')
  [[ "$snapshot_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] ||
    die 'retained snapshot UUID invalid'
  printf -v dns_mode '%04d' "$(stat -c '%a' "$dns_ini")"
  render_sha=$(docker-compose --project-name networking --env-file "$env_file" --env-file "$vault_env" -f "$compose_file" config --no-interpolate --no-env-resolution 2>/dev/null | sha256sum | awk '{print $1}') ||
    die 'value-free Compose render failed'
  jq -n \
    --slurpfile runtime "$runtime" \
    --arg approved_inventory_path "$saved_inventory" --arg approved_inventory_sha "$(sha256sum "$saved_inventory" | awk '{print $1}')" \
    --arg authorization_path "$saved_authorization" --arg authorization_sha "$(sha256sum "$saved_authorization" | awk '{print $1}')" \
    --arg ledger_path "$ledger" --arg ledger_sha "$(sha256sum "$ledger" | awk '{print $1}')" \
    --arg archive_path "$archive" --arg archive_sha "$(sha256sum "$archive" | awk '{print $1}')" \
    --arg checksum_path "$archive_sha256" --arg checksum_sha "$(sha256sum "$archive_sha256" | awk '{print $1}')" \
    --arg snapshot_path "$snapshot" --arg snapshot_uuid "$snapshot_uuid" \
    --arg credential_path "$dns_ini" --arg credential_mode "$dns_mode" --arg credential_owner "$(stat -c '%u:%g' "$dns_ini")" \
    --arg servarr_commit "$(git -C "$repository" rev-parse HEAD)" --arg compose_file "$compose_file" \
    --arg render_sha256 "$render_sha" \
    '{dns_file_metadata:{path:$credential_path,mode:$credential_mode,owner:$credential_owner},current_runtime:{containers:$runtime[0].containers},retained:{
      approved_inventory:{path:$approved_inventory_path,sha256:$approved_inventory_sha},
      archive:{path:$archive_path,sha256:$archive_sha},
      archive_checksum:{path:$checksum_path,sha256:$checksum_sha},
      authorization:{path:$authorization_path,sha256:$authorization_sha},
      ledger:{path:$ledger_path,sha256:$ledger_sha},
      snapshot:{path:$snapshot_path,uuid:$snapshot_uuid}},servarr:{commit:$servarr_commit,compose_file:$compose_file,render_sha256:$render_sha256}}' >"$output"
}

assert_resume_contract() {
  jq -e --arg predecessor_manifest "$predecessor_manifest_sha" --arg predecessor_inventory "$predecessor_inventory_sha" '
    .manifest.version == 2 and .manifest.mode == "resume-attempt-02" and
    .manifest.predecessor == {manifest_sha256:$predecessor_manifest,inventory_sha256:$predecessor_inventory} and
    .manifest.workflow_contract == {version:2,phase_markers:["init-complete","swag-complete","validation-complete"],resume_policy:{
      completed:"revalidate-all-bindings-identities-and-gates",compose_consistency:"declarative-no-interpolate-hash-before-and-after-each-up",
      init_without_marker:["approved-pre-state","exact-post-init-state"],
      markers:"monotonic-no-overwrite",swag_without_marker:["approved-swag-id","exact-desired-post-state"]},execute_order:[
      "verify-predecessor-and-retained-evidence", "capture-and-bind-post-recreate-runtime",
      "validate-attempt-02-no-clobber-evidence-set", "persist-attempt-02-authorization-and-observation",
      "recreate-swag-init", "recreate-swag",
      "validate-owner-mode-health-certificate-dns-and-routes", "persist-attempt-02-result"]}
  ' "$1" >/dev/null || die 'attempt-02 workflow contract differs'
}

assert_dns_owner_mode() {
  [ "$(stat -c '%a' "$dns_ini")" = 600 ] || die 'DNS credential mode is not 0600'
  [ "$(stat -c '%u:%g' "$dns_ini")" = 1000:100 ] || die 'DNS credential ownership differs'
}

observe_attempt_02_main() {
  local runtime observation
  [ "$(id -u)" -eq 0 ] || die 'must run as root'
  assert_retained_binding "$predecessor_manifest_sha"
  [ "$(jq -r '.manifest.inventory_sha256' "$saved_authorization")" = "$predecessor_inventory_sha" ] || die 'predecessor inventory SHA-256 differs'
  runtime=$(mktemp)
  observation=$(mktemp)
  trap 'rm -f "$runtime" "$observation"' EXIT
  capture_resume_observation "$runtime" "$observation"
  cat "$observation"
}

assert_fresh_compose_binding() {
  local authorization_file=$1 commit render_sha
  commit=$(git -C "$repository" rev-parse HEAD) || die 'Servarr commit unavailable'
  render_sha=$(docker-compose --project-name networking --env-file "$env_file" --env-file "$vault_env" -f "$compose_file" config --no-interpolate --no-env-resolution 2>/dev/null | sha256sum | awk '{print $1}') ||
    die 'value-free Compose render failed'
  [ "$commit" = "$(jq -r '.manifest.servarr.commit' "$authorization_file")" ] || die 'current Servarr commit differs'
  [ "$render_sha" = "$(jq -r '.manifest.servarr.render_sha256' "$authorization_file")" ] || die 'current rendered Compose differs'
}

assert_stored_resume_binding() {
  local supplied_authorization=$1
  cmp --silent "$supplied_authorization" "$attempt_02_authorization" || die 'attempt-02 authorization collision'
  discovery-stateful-swag-preflight resume-verify "$attempt_02_observation" "$attempt_02_authorization" >/dev/null ||
    die 'stored attempt-02 observation binding invalid'
}

assert_retained_resume_hashes() {
  local authorization_file=$1 snapshot_uuid
  snapshot_uuid=$(btrfs subvolume show "$snapshot" | awk '/UUID:/ && !/Parent|Received/ {print $2; exit}')
  jq -e \
    --arg approved_inventory "$(sha256sum "$saved_inventory" | awk '{print $1}')" \
    --arg authorization "$(sha256sum "$saved_authorization" | awk '{print $1}')" \
    --arg ledger "$(sha256sum "$ledger" | awk '{print $1}')" \
    --arg archive "$(sha256sum "$archive" | awk '{print $1}')" \
    --arg archive_checksum "$(sha256sum "$archive_sha256" | awk '{print $1}')" \
    --arg snapshot_uuid "$snapshot_uuid" '
    .manifest.retained.approved_inventory.sha256 == $approved_inventory and
    .manifest.retained.authorization.sha256 == $authorization and
    .manifest.retained.ledger.sha256 == $ledger and .manifest.retained.archive.sha256 == $archive and
    .manifest.retained.archive_checksum.sha256 == $archive_checksum and .manifest.retained.snapshot.uuid == $snapshot_uuid
  ' "$authorization_file" >/dev/null || die 'current retained evidence differs from attempt-02 authorization'
}

assert_phase_journal_shape() {
  local entry name
  [ -d "$attempt_02_phases" ] || die 'attempt-02 phase journal absent'
  shopt -s nullglob
  for entry in "$attempt_02_phases"/*; do
    name=${entry##*/}
    [ -d "$entry" ] || die 'attempt-02 phase marker is not a directory'
    case "$name" in init-complete | swag-complete | validation-complete) ;; *) die 'unknown attempt-02 phase marker' ;; esac
  done
  shopt -u nullglob
  [ ! -d "$swag_complete" ] || [ -d "$init_complete" ] || die 'attempt-02 phase journal order invalid'
  [ ! -d "$validation_complete" ] || [ -d "$swag_complete" ] || die 'attempt-02 phase journal order invalid'
}

assert_current_desired_runtime() {
  local runtime_file=$1
  jq -e --arg working_dir "$repository/machines/discovery" --arg source "$repository/machines/discovery/config/swag" \
    --arg swag_image "$image" --arg init_image 'busybox:1.38@sha256:fd8d9aa63ba2f0982b5304e1ee8d3b90a210bc1ffb5314d980eb6962f1a9715d' '
    (.containers | length) == 2 and ([.containers[].name] | sort) == ["swag","swag-init"] and
    all(.containers[]; .compose_project == "networking" and .compose_working_dir == $working_dir and
      .compose_service == .name and (.id | test("^[0-9a-f]{64}$")) and
      (.image_id | test("^sha256:[0-9a-f]{64}$")) and
      .mounts == [{source:$source,target:"/config",type:"bind"}]) and
    (.containers[] | select(.name == "swag") | .state == "running" and .image_ref == $swag_image) and
    (.containers[] | select(.name == "swag-init") | .state == "exited" and .image_ref == $init_image)
  ' "$runtime_file" >/dev/null || die 'current swag-init identity differs or current runtime is not exact desired state'
}

assert_final_gates() {
  local health adguard_code png temporary_png=false
  for _ in $(seq 1 60); do
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' swag 2>/dev/null || true)
    [ "$health" = healthy ] && break
    sleep 2
  done
  [ "${health:-}" = healthy ] || die "SWAG failed health gate: ${health:-missing}"
  assert_dns_owner_mode
  discovery-stateful-stack-ops smoke "$ledger" --expect-image-ref "$image"
  docker exec swag nginx -t
  openssl x509 -in "$cert" -noout -checkend 604800 >/dev/null || die 'certificate expires within seven days'
  openssl x509 -in "$cert" -noout -text | grep -Fq 'DNS:*.homelab.pastelariadev.com' || die 'wildcard SAN absent'
  docker exec swag certbot renew --dry-run --no-random-sleep-on-renew
  curl --resolve grafana.homelab.pastelariadev.com:443:192.168.10.210 --fail --silent --show-error --max-time 15 https://grafana.homelab.pastelariadev.com/api/health >/dev/null
  adguard_code=$(curl --resolve adguard.homelab.pastelariadev.com:443:192.168.10.210 --silent --show-error --max-time 15 --output /dev/null --write-out '%{http_code}' https://adguard.homelab.pastelariadev.com/)
  [ "$adguard_code" = 302 ] || die "AdGuard ingress returned $adguard_code"
  png=$attempt_02_kindle_png
  if [ -e "$png" ]; then
    png=$(mktemp)
    temporary_png=true
  fi
  curl --resolve kindle.homelab.pastelariadev.com:80:192.168.10.210 --fail --silent --show-error --max-time 30 http://kindle.homelab.pastelariadev.com/dash.png --output "$png"
  [ "$(od -An -tx1 -N8 "$png" | tr -d ' \n')" = 89504e470d0a1a0a ] || die 'Kindle route did not return PNG'
  if $temporary_png; then rm -f "$png"; else chmod 0400 "$png"; fi
}

resume_attempt_02_main() {
  local authorization_file=$1 expected_sha=$2 runtime observation verification actual_sha checksum checksum_path initial_swag_id initial_init_id current_swag_id current_init_id result_tmp prepare lock
  [ "$(id -u)" -eq 0 ] || die 'must run as root'
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die 'approved resume manifest SHA-256 invalid'
  [ -f "$authorization_file" ] || die 'resume authorization absent'
  assert_resume_contract "$authorization_file"
  actual_sha=$(jq -er '.manifest_sha256 | select(test("^[0-9a-f]{64}$"))' "$authorization_file") || die 'resume manifest SHA-256 absent'
  [ "$actual_sha" = "$expected_sha" ] || die 'approved resume manifest SHA-256 differs'
  lock="/run/lock/servarr-repository.lock"
  [ -f "$lock" ] && [ ! -L "$lock" ] || die 'declarative Servarr repository lock invalid'
  [ "$(stat -c '%U:%G:%a' "$lock")" = root:users:660 ] || die 'declarative Servarr repository lock ownership differs'
  exec 9>"$lock"
  flock 9
  assert_retained_binding "$predecessor_manifest_sha"
  [ "$(jq -r '.manifest.inventory_sha256' "$saved_authorization")" = "$predecessor_inventory_sha" ] || die 'predecessor inventory SHA-256 differs'
  [ -f "$archive" ] && [ -f "$archive_sha256" ] && [ -d "$snapshot" ] || die 'retained recovery evidence incomplete'
  read -r checksum checksum_path <"$archive_sha256" || die 'retained archive checksum unreadable'
  [ "$checksum_path" = "$archive" ] || die 'retained archive checksum target differs'
  [ "$(sha256sum "$archive" | awk '{print $1}')" = "$checksum" ] || die 'retained archive checksum differs'
  assert_retained_resume_hashes "$authorization_file"

  runtime=$(mktemp)
  observation=$(mktemp)
  trap 'rm -f "${runtime:-}" "${observation:-}" "${result_tmp:-}" "${stdin_authorization:-}"; [ -z "${prepare:-}" ] || { rm -f "$prepare/authorization.json" "$prepare/observation.json"; rmdir "$prepare/phases" "$prepare" 2>/dev/null || true; }' EXIT

  # A fully recorded successful attempt is a verified no-op, not a result-file shortcut.
  if [ -f "$attempt_02_result" ]; then
    [ -f "$attempt_02_authorization" ] && [ -f "$attempt_02_observation" ] && [ -f "$attempt_02_post_runtime" ] &&
      [ -d "$init_complete" ] && [ -d "$swag_complete" ] && [ -d "$validation_complete" ] || die 'completed attempt-02 evidence incomplete'
    assert_phase_journal_shape
    assert_stored_resume_binding "$authorization_file"
    assert_fresh_compose_binding "$attempt_02_authorization"
    discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'current runtime capture failed'
    assert_current_desired_runtime "$runtime"
    cmp --silent "$runtime" "$attempt_02_post_runtime" || die 'current exact container identities differ from recorded post-state'
    assert_final_gates
    jq -e --arg sha "$expected_sha" --arg post_sha "$(sha256sum "$attempt_02_post_runtime" | awk '{print $1}')" '
      .version == 2 and .status == "passed" and .manifest_sha256 == $sha and .post_runtime_sha256 == $post_sha
    ' "$attempt_02_result" >/dev/null || die 'attempt-02 result invalid'
    cat "$attempt_02_result"
    return
  fi

  if [ ! -e "$attempt_02" ]; then
    capture_resume_observation "$runtime" "$observation"
    verification=$(discovery-stateful-swag-preflight resume-verify "$observation" "$authorization_file") || die 'resume observation differs from authorization'
    [ "$(jq -r '.status' <<<"$verification")" = resume-binding-valid ] || die 'resume authorization binding invalid'
    prepare=$(mktemp -d "$evidence/.attempt-02.prepare.XXXXXX")
    chmod 0700 "$prepare"
    install -m 0400 "$authorization_file" "$prepare/authorization.json"
    install -m 0400 "$observation" "$prepare/observation.json"
    mkdir "$prepare/phases"
    mv "$prepare" "$attempt_02"
    prepare=
  else
    [ -d "$attempt_02" ] && [ -d "$attempt_02_phases" ] && [ -f "$attempt_02_authorization" ] && [ -f "$attempt_02_observation" ] ||
      die 'partial attempt-02 evidence shape invalid'
    assert_stored_resume_binding "$authorization_file"
  fi
  assert_phase_journal_shape
  assert_fresh_compose_binding "$attempt_02_authorization"
  discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'current runtime capture failed'
  initial_swag_id=$(jq -r '.manifest.current_runtime.containers[] | select(.name == "swag") | .id' "$attempt_02_authorization")
  initial_init_id=$(jq -r '.manifest.current_runtime.containers[] | select(.name == "swag-init") | .id' "$attempt_02_authorization")
  current_swag_id=$(jq -r '.containers[] | select(.name == "swag") | .id' "$runtime")

  export DOCKER_HOST=unix:///run/docker.sock
  compose=(docker-compose --project-name networking --env-file "$env_file" --env-file "$vault_env" -f "$compose_file")
  if [ ! -d "$init_complete" ]; then
    if cmp --silent <(jq -S '.containers' "$runtime") <(jq -S '.manifest.current_runtime.containers' "$attempt_02_authorization") &&
      [ "$(stat -c '%a:%u:%g' "$dns_ini")" = 600:0:0 ]; then
      assert_fresh_compose_binding "$attempt_02_authorization"
      "${compose[@]}" up --no-deps --force-recreate --abort-on-container-exit --exit-code-from swag-init swag-init
      assert_fresh_compose_binding "$attempt_02_authorization"
    else
      assert_current_desired_runtime "$runtime"
      [ "$current_swag_id" = "$initial_swag_id" ] && [ "$(stat -c '%a:%u:%g' "$dns_ini")" = 600:1000:100 ] ||
        die 'current SWAG identity is neither approved pre-state nor desired post-state'
    fi
    discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'post-init runtime capture failed'
    assert_current_desired_runtime "$runtime"
    current_swag_id=$(jq -r '.containers[] | select(.name == "swag") | .id' "$runtime")
    current_init_id=$(jq -r '.containers[] | select(.name == "swag-init") | .id' "$runtime")
    [ "$current_swag_id" = "$initial_swag_id" ] || die 'SWAG changed before init-complete marker'
    [ "$current_init_id" != "$initial_init_id" ] || die 'swag-init recreation did not change runtime identity'
    assert_dns_owner_mode
    mkdir "$init_complete"
  else
    assert_current_desired_runtime "$runtime"
    assert_dns_owner_mode
  fi

  discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'post-init runtime capture failed'
  assert_current_desired_runtime "$runtime"
  current_swag_id=$(jq -r '.containers[] | select(.name == "swag") | .id' "$runtime")
  current_init_id=$(jq -r '.containers[] | select(.name == "swag-init") | .id' "$runtime")
  [ "$current_init_id" != "$initial_init_id" ] || die 'current swag-init identity differs from required post-init state'
  if [ ! -d "$swag_complete" ]; then
    if [ "$current_swag_id" = "$initial_swag_id" ]; then
      assert_fresh_compose_binding "$attempt_02_authorization"
      "${compose[@]}" up -d --no-deps --force-recreate swag
      assert_fresh_compose_binding "$attempt_02_authorization"
    fi
    discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'post-recreate runtime capture failed'
    assert_current_desired_runtime "$runtime"
    current_swag_id=$(jq -r '.containers[] | select(.name == "swag") | .id' "$runtime")
    [ "$current_swag_id" != "$initial_swag_id" ] || die 'SWAG recreation did not change runtime identity'
    mkdir "$swag_complete"
  fi

  discovery-stateful-swag-inventory capture-runtime >"$runtime" || die 'final runtime capture failed'
  assert_current_desired_runtime "$runtime"
  if [ -f "$attempt_02_post_runtime" ]; then
    cmp --silent "$runtime" "$attempt_02_post_runtime" || die 'recorded post-runtime collision'
  else
    install -m 0400 "$runtime" "$attempt_02_post_runtime"
  fi
  assert_final_gates
  [ -d "$validation_complete" ] || mkdir "$validation_complete"

  result_tmp=$(mktemp)
  jq -n --arg completed_at "$(date --utc --iso-8601=seconds)" --arg manifest_sha256 "$expected_sha" \
    --arg post_runtime_sha256 "$(sha256sum "$attempt_02_post_runtime" | awk '{print $1}')" \
    '{version:2,status:"passed",$completed_at,$manifest_sha256,$post_runtime_sha256,predecessor_retained:true}' >"$result_tmp"
  install -m 0400 "$result_tmp" "$attempt_02_result"
  cat "$attempt_02_result"
}

assert_workflow_contract() {
  # Keep this literal synchronized with WORKFLOW_CONTRACT in the planner.
  # Any workflow semantic change requires an action change or version bump.
  jq -e '
    .manifest.workflow_contract == {
      version: 1,
      execute_order: [
        "capture-and-verify-fresh-inventory",
        "validate-no-clobber-evidence-set",
        "persist-authorization-and-inventory",
        "create-ledger-and-baseline",
        "reinspect-both-container-identities",
        "stop-captured-swag-id",
        "snapshot-and-archive-stopped-state",
        "recreate-swag-init-then-swag",
        "validate-health-state-certificate-and-routes",
        "persist-result-and-rollback-evidence"
      ],
      rollback: {
        implementation: "fixed-compose-swag-recreate-v1",
        pre_adoption_recovery: "start-exact-stopped-approved-swag-id-v1",
        required_retained_evidence: [
          "approved_inventory", "authorization", "archive", "archive_sha256", "ledger", "snapshot"
        ]
      }
    }
  ' "$1" >/dev/null || die 'workflow action/rollback contract differs'
}

protection_failure() {
  die "stopped-state protection failed; SWAG remains stopped and partial evidence is retained; inspect it, then use the fixed pre-adoption recovery entrypoint: discovery-stateful-swag-adopt recover-pre-adoption --manifest-sha $1"
}

authorize_fresh_inventory() {
  local authorization_file=$1 expected_sha=$2 actual_sha verification
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die 'approved manifest SHA-256 invalid'
  [ -f "$authorization_file" ] || die "authorization absent: $authorization_file"
  assert_workflow_contract "$authorization_file"
  fresh_inventory=$(mktemp)
  trap 'rm -f "${fresh_inventory:-}" "${stdin_authorization:-}"' EXIT
  discovery-stateful-swag-inventory capture >"$fresh_inventory" || die 'fresh inventory capture failed'
  verification=$(discovery-stateful-swag-preflight verify "$fresh_inventory" "$authorization_file") ||
    die 'fresh inventory differs from authorization'
  actual_sha=$(jq -er '.manifest_sha256 | select(test("^[0-9a-f]{64}$"))' "$authorization_file") ||
    die 'authorization manifest SHA-256 absent'
  [ "$actual_sha" = "$expected_sha" ] || die 'approved manifest SHA-256 differs'
  [ "$(jq -r '.status' <<<"$verification")" = binding-valid ] || die 'authorization binding invalid'
}

assert_exact_ledger() {
  jq -e --arg repository "$repository" --arg snapshot "$snapshot" --arg archive "$archive" \
    --arg restore_target "$restore_target" --arg rollback "$rollback_description" --arg image "$image" --arg image_digest "$image_digest" '
    (keys | sort) == (["archive_id", "compose_owner", "compose_project", "container", "copy_destination",
      "expected_downtime", "git_commit", "image_digest", "image_tag", "mount_target", "ownership",
      "physical_source", "physical_volume", "recorded_at", "rollback_command", "size_bytes", "snapshot_id",
      "snapshot_source", "version", "volume_type"] | sort) and
    .version == 1 and .container == "swag" and .compose_project == "networking" and
    .compose_owner == ($repository + "/machines/discovery") and .mount_target == "/config" and
    .physical_source == ($repository + "/machines/discovery/config/swag") and
    .physical_volume == .physical_source and .volume_type == "bind" and
    .snapshot_source == "/home" and .snapshot_id == $snapshot and .archive_id == $archive and
    .copy_destination == $restore_target and .rollback_command == $rollback and
    .expected_downtime == "up to 2 minutes" and .image_tag == $image and .image_digest == $image_digest and
    (.git_commit | test("^[0-9a-f]{40}$")) and (.ownership | test("^[0-9]+:[0-9]+$")) and
    (.size_bytes | type == "number" and . >= 0)
  ' "$ledger" >/dev/null || die 'retained ledger identity differs'
}

assert_retained_binding() {
  local expected_sha=$1 actual_sha
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die 'approved manifest SHA-256 invalid'
  [ -f "$saved_authorization" ] || die 'retained authorization absent'
  [ -f "$saved_inventory" ] || die 'retained approved inventory absent'
  assert_workflow_contract "$saved_authorization"
  actual_sha=$(jq -er '.manifest_sha256 | select(test("^[0-9a-f]{64}$"))' "$saved_authorization") ||
    die 'retained authorization invalid'
  [ "$actual_sha" = "$expected_sha" ] || die 'retained manifest SHA-256 differs'
  discovery-stateful-swag-preflight verify "$saved_inventory" "$saved_authorization" >/dev/null ||
    die 'retained authorization binding invalid'
  assert_exact_ledger
}

recover_pre_adoption_main() {
  local expected_sha=$1 runtime_inventory expected_containers actual_containers swag_id
  [ "$(id -u)" -eq 0 ] || die 'must run as root'
  assert_retained_binding "$expected_sha"
  runtime_inventory=$(mktemp)
  expected_containers=$(mktemp)
  actual_containers=$(mktemp)
  trap 'rm -f "${runtime_inventory:-}" "${expected_containers:-}" "${actual_containers:-}"' EXIT
  discovery-stateful-swag-inventory capture-runtime >"$runtime_inventory" || die 'pre-adoption recovery inventory failed'
  jq -S '.containers | map(if .name == "swag" then .state = "exited" else . end)' "$saved_inventory" >"$expected_containers"
  jq -S '.containers' "$runtime_inventory" >"$actual_containers"
  cmp --silent "$expected_containers" "$actual_containers" || die 'pre-adoption recovery container identity differs'
  swag_id=$(jq -er '.containers[] | select(.name == "swag") | .id | select(test("^[0-9a-f]{64}$"))' "$saved_inventory") ||
    die 'approved SWAG container ID absent'
  [ "$(docker inspect --format '{{.State.Running}}' "$swag_id")" = false ] || die 'approved SWAG container is not stopped'
  docker start "$swag_id" >/dev/null
  [ "$(docker inspect --format '{{.State.Running}}' "$swag_id")" = true ] || die 'approved SWAG container did not restart'
}

rollback_main() {
  local expected_sha=$1 checksum checksum_path
  [ "$(id -u)" -eq 0 ] || die 'must run as root'
  assert_retained_binding "$expected_sha"
  [ -f "$archive" ] || die 'retained archive absent'
  [ -f "$archive_sha256" ] || die 'retained archive checksum absent'
  read -r checksum checksum_path <"$archive_sha256" || die 'retained archive checksum unreadable'
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || die 'retained archive checksum invalid'
  [ "$checksum_path" = "$archive" ] || die 'retained archive checksum target differs'
  [ "$(sha256sum "$archive" | awk '{print $1}')" = "$checksum" ] || die 'retained archive checksum differs'
  [ -d "$snapshot" ] || die 'retained snapshot absent'
  btrfs subvolume show "$snapshot" >/dev/null 2>&1 || die 'retained snapshot identity invalid'
  [ -f "$compose_file" ] || die "Compose file absent: $compose_file"
  [ -f "$env_file" ] || die "Compose environment absent: $env_file"
  [ -f "$vault_env" ] || die "Vault environment absent: $vault_env"
  export DOCKER_HOST=unix:///run/docker.sock
  docker-compose --project-name networking --env-file "$env_file" --env-file "$vault_env" \
    -f "$compose_file" up -d --no-deps --force-recreate swag
}

execute_main() {
local authorization_file=$1 expected_sha=$2 fresh_inventory
[ "$(id -u)" -eq 0 ] || die 'must run as root'
authorize_fresh_inventory "$authorization_file" "$expected_sha"
[ -f "$compose_file" ] || die "Compose file absent: $compose_file"
[ -f "$env_file" ] || die "Compose environment absent: $env_file"
[ -f "$vault_env" ] || die "Vault environment absent: $vault_env"
[ -f "$cert" ] || die "certificate absent: $cert"
[ -f "$dns_ini" ] || die "DNS credential path absent: $dns_ini"
for path in "$ledger" "$baseline" "$result" "$saved_inventory" "$saved_authorization" "$rollback_evidence" "$kindle_png" "$snapshot" "$archive" "$archive_sha256" "$restore_target"; do
  [ ! -e "$path" ] || die "P1 evidence resource already exists: $path"
done

mkdir -p "$evidence"
chmod 0700 "$evidence"
install -m 0400 "$fresh_inventory" "$saved_inventory"
install -m 0400 "$authorization_file" "$saved_authorization"

inspect=$(docker inspect swag 2>/dev/null) || die 'SWAG container absent'
[ "$(jq -r '.[0].State.Running' <<<"$inspect")" = true ] || die 'SWAG is not running'
[ "$(jq -r '.[0].State.Health.Status' <<<"$inspect")" = healthy ] || die 'SWAG is not healthy'
[ "$(jq -r '.[0].Config.Labels["com.docker.compose.project"]' <<<"$inspect")" = networking ] || die 'SWAG project owner differs'
[ "$(jq -r '.[0].Config.Labels["com.docker.compose.project.working_dir"]' <<<"$inspect")" = "$repository/machines/discovery" ] || die 'SWAG Compose owner differs'

discovery-stateful-stack-ops ledger-create \
  "$ledger" "$repository" swag /config /home "$snapshot" "$archive" \
  "$restore_target" "$rollback_description" 'up to 2 minutes' >/dev/null

cert_sha=$(sha256sum "$cert" | awk '{print $1}')
cert_fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2)
jq -n \
  --arg recorded_at "$(date --utc --iso-8601=seconds)" \
  --arg ledger "$ledger" \
  --arg cert_sha256 "$cert_sha" \
  --arg cert_fingerprint_sha256 "$cert_fingerprint" \
  --arg cert_not_before "$(openssl x509 -in "$cert" -noout -startdate | cut -d= -f2-)" \
  --arg cert_not_after "$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2-)" \
  --arg dns_ini_mode "$(stat -c '%a' "$dns_ini")" \
  '{version:1,$recorded_at,$ledger,$cert_sha256,$cert_fingerprint_sha256,$cert_not_before,$cert_not_after,$dns_ini_mode}' \
  >"$baseline"
chmod 0400 "$baseline"

started=$(date +%s)
runtime_inventory=$(mktemp)
approved_containers=$(mktemp)
runtime_containers=$(mktemp)
trap 'rm -f "${fresh_inventory:-}" "${stdin_authorization:-}" "${runtime_inventory:-}" "${approved_containers:-}" "${runtime_containers:-}"' EXIT
discovery-stateful-swag-inventory capture-runtime >"$runtime_inventory" || die 'immediate container reinspection failed'
jq -S '.containers' "$saved_inventory" >"$approved_containers"
jq -S '.containers' "$runtime_inventory" >"$runtime_containers"
cmp --silent "$approved_containers" "$runtime_containers" || die 'container identity drift immediately before stop'
swag_id=$(jq -er '.containers[] | select(.name == "swag") | .id | select(test("^[0-9a-f]{64}$"))' "$saved_inventory") ||
  die 'approved SWAG container ID absent'
docker stop --time 30 "$swag_id" >/dev/null
discovery-stateful-stack-ops snapshot "$ledger" || protection_failure "$expected_sha"
discovery-stateful-stack-ops archive "$ledger" || protection_failure "$expected_sha"

export DOCKER_HOST=unix:///run/docker.sock
compose=(docker-compose --project-name networking --env-file "$env_file" --env-file "$vault_env" -f "$compose_file")
"${compose[@]}" up --no-deps --force-recreate --abort-on-container-exit --exit-code-from swag-init swag-init
"${compose[@]}" up -d --no-deps --force-recreate swag

for _ in $(seq 1 60); do
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' swag 2>/dev/null || true)
  [ "$health" = healthy ] && break
  sleep 2
done
[ "${health:-}" = healthy ] || die "SWAG failed health gate: ${health:-missing}"

discovery-stateful-stack-ops smoke "$ledger" --expect-image-ref "$image"
docker exec swag nginx -t

[ "$(stat -c '%a' "$dns_ini")" = 600 ] || die "DNS credential mode is not 0600"
[ "$(stat -c '%u:%g' "$dns_ini")" = 1000:100 ] || die "DNS credential ownership differs"
[ "$(sed -n 's/^dns_cloudflare_api_token = //p' "$dns_ini" | wc -c)" -gt 20 ] || die "DNS credential content missing"

[ "$(sha256sum "$cert" | awk '{print $1}')" = "$cert_sha" ] || die 'certificate content changed during ownership adoption'
openssl x509 -in "$cert" -noout -checkend 604800 >/dev/null || die 'certificate expires within seven days'
openssl x509 -in "$cert" -noout -text | grep -Fq 'DNS:*.homelab.pastelariadev.com' || die 'wildcard SAN absent'
docker exec swag certbot renew --dry-run --no-random-sleep-on-renew

curl --resolve grafana.homelab.pastelariadev.com:443:192.168.10.210 \
  --fail --silent --show-error --max-time 15 \
  https://grafana.homelab.pastelariadev.com/api/health >/dev/null
adguard_code=$(curl --resolve adguard.homelab.pastelariadev.com:443:192.168.10.210 \
  --silent --show-error --max-time 15 --output /dev/null --write-out '%{http_code}' \
  https://adguard.homelab.pastelariadev.com/)
[ "$adguard_code" = 302 ] || die "AdGuard ingress returned $adguard_code"
curl --resolve kindle.homelab.pastelariadev.com:80:192.168.10.210 \
  --fail --silent --show-error --max-time 30 \
  http://kindle.homelab.pastelariadev.com/dash.png --output "$kindle_png"
[ "$(od -An -tx1 -N8 "$kindle_png" | tr -d ' \n')" = 89504e470d0a1a0a ] || die 'Kindle route did not return PNG'

discovery-stateful-stack-ops rollback-evidence "$ledger" >"$rollback_evidence"
chmod 0400 "$rollback_evidence" "$kindle_png"
ended=$(date +%s)
jq -n \
  --arg completed_at "$(date --utc --iso-8601=seconds)" \
  --arg git_commit "$(jq -r '.git_commit' "$ledger")" \
  --arg image "$image" \
  --arg image_digest "$(jq -r '.image_digest' "$ledger")" \
  --arg snapshot "$snapshot" \
  --arg snapshot_uuid "$(btrfs subvolume show "$snapshot" | awk '/UUID:/ && !/Parent|Received/ {print $2; exit}')" \
  --arg archive "$archive" \
  --arg archive_sha256 "$(awk '{print $1}' "${archive}.sha256")" \
  --arg cert_fingerprint_sha256 "$cert_fingerprint" \
  --argjson downtime_seconds "$((ended - started))" \
  --arg physical_volume "$(jq -r '.physical_volume' "$ledger")" \
  --arg mount "$(jq -r '.mount_target' "$ledger")" \
  --arg ownership "$(jq -r '.ownership' "$ledger")" \
  --argjson size_bytes "$(jq -r '.size_bytes' "$ledger")" \
  '{version:1,status:"passed",$completed_at,$git_commit,compose_project:"networking",compose_owner:"/home/erik/servarr/machines/discovery",$image,$image_digest,$physical_volume,$mount,$size_bytes,$ownership,$snapshot,$snapshot_uuid,$archive,$archive_sha256,$cert_fingerprint_sha256,$downtime_seconds,legacy_resources_retained:true}' \
  >"$result"
chmod 0400 "$result"
cat "$result"
}

command=${1:-}
shift || true
case "$command" in
  execute)
    [ "${1:-}" = --authorization ] || usage
    authorization_file=${2:-}
    [ "${3:-}" = --manifest-sha ] || usage
    manifest_sha=${4:-}
    [ "$#" -eq 4 ] || usage
    if [ "$authorization_file" = - ]; then
      stdin_authorization=$(mktemp)
      trap 'rm -f "$stdin_authorization"' EXIT
      cat >"$stdin_authorization"
      authorization_file=$stdin_authorization
    fi
    execute_main "$authorization_file" "$manifest_sha"
    ;;
  rollback)
    [ "${1:-}" = --manifest-sha ] || usage
    [ "$#" -eq 2 ] || usage
    rollback_main "${2:-}"
    ;;
  recover-pre-adoption)
    [ "${1:-}" = --manifest-sha ] || usage
    [ "$#" -eq 2 ] || usage
    recover_pre_adoption_main "${2:-}"
    ;;
  resume-attempt-02)
    [ "${1:-}" = --authorization ] || usage
    authorization_file=${2:-}
    [ "${3:-}" = --manifest-sha ] || usage
    manifest_sha=${4:-}
    [ "$#" -eq 4 ] || usage
    if [ "$authorization_file" = - ]; then
      stdin_authorization=$(mktemp)
      trap 'rm -f "$stdin_authorization"' EXIT
      cat >"$stdin_authorization"
      authorization_file=$stdin_authorization
    fi
    resume_attempt_02_main "$authorization_file" "$manifest_sha"
    ;;
  observe-attempt-02)
    [ "$#" -eq 0 ] || usage
    observe_attempt_02_main
    ;;
  *) usage ;;
esac
