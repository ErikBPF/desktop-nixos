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
  exit 2
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
  *) usage ;;
esac
