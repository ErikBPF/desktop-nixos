# shellcheck shell=bash
set -euo pipefail
umask 077

readonly repository=/home/erik/servarr
readonly compose_file=$repository/machines/discovery/networking.yml
readonly env_file=$repository/machines/discovery/.env
readonly vault_env=/run/vault-agent/networking.env
readonly evidence=/var/lib/stateful-stack-migrations/p1-swag-20260713
readonly ledger=$evidence/ledger.json
readonly baseline=$evidence/baseline.json
readonly result=$evidence/result.json
readonly snapshot=/home/.snapshots/stateful-stack-p1-swag-20260713
readonly archive=$evidence/swag-config.tar.zst
readonly restore_target=$evidence/restore-only-after-approval
readonly image='lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d'
readonly cert=/home/erik/servarr/machines/discovery/config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/fullchain.pem
readonly dns_ini=/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini
readonly rollback='DOCKER_HOST=unix:///run/docker.sock docker-compose --project-name networking --env-file /home/erik/servarr/machines/discovery/.env --env-file /run/vault-agent/networking.env -f /home/erik/servarr/machines/discovery/networking.yml up -d --no-deps --force-recreate swag'

die() {
  echo "stateful-swag-adopt: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || die 'must run as root'
[ -f "$compose_file" ] || die "Compose file absent: $compose_file"
[ -f "$env_file" ] || die "Compose environment absent: $env_file"
[ -f "$vault_env" ] || die "Vault environment absent: $vault_env"
[ -f "$cert" ] || die "certificate absent: $cert"
[ -f "$dns_ini" ] || die "DNS credential path absent: $dns_ini"
for path in "$ledger" "$baseline" "$result" "$snapshot" "$archive" "${archive}.sha256" "$restore_target"; do
  [ ! -e "$path" ] || die "P1 evidence resource already exists: $path"
done

mkdir -p "$evidence"
chmod 0700 "$evidence"

inspect=$(docker inspect swag 2>/dev/null) || die 'SWAG container absent'
[ "$(jq -r '.[0].State.Running' <<<"$inspect")" = true ] || die 'SWAG is not running'
[ "$(jq -r '.[0].State.Health.Status' <<<"$inspect")" = healthy ] || die 'SWAG is not healthy'
[ "$(jq -r '.[0].Config.Labels["com.docker.compose.project"]' <<<"$inspect")" = networking ] || die 'SWAG project owner differs'
[ "$(jq -r '.[0].Config.Labels["com.docker.compose.project.working_dir"]' <<<"$inspect")" = "$repository/machines/discovery" ] || die 'SWAG Compose owner differs'

discovery-stateful-stack-ops ledger-create \
  "$ledger" "$repository" swag /config /home "$snapshot" "$archive" \
  "$restore_target" "$rollback" 'up to 2 minutes' >/dev/null

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
docker stop --time 30 swag >/dev/null
discovery-stateful-stack-ops snapshot "$ledger"
discovery-stateful-stack-ops archive "$ledger"

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
  http://kindle.homelab.pastelariadev.com/dash.png --output "$evidence/kindle.png"
[ "$(od -An -tx1 -N8 "$evidence/kindle.png" | tr -d ' \n')" = 89504e470d0a1a0a ] || die 'Kindle route did not return PNG'

discovery-stateful-stack-ops rollback-evidence "$ledger" >"$evidence/rollback-evidence.txt"
chmod 0400 "$evidence/rollback-evidence.txt" "$evidence/kindle.png"
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
