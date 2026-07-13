# shellcheck shell=bash
set -euo pipefail
umask 077

readonly container=stateful-stack-p0-fixture
readonly image='lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d'
readonly repository=/home/erik/servarr
readonly root=/home/.stateful-stack-fixtures/p0
readonly source_path=$root/source
readonly destination_path=$root/restored
readonly evidence=/var/lib/stateful-stack-migrations/p0-fixture
readonly plan=$evidence/pre-mutation.json
readonly ledger=$evidence/ledger.json
readonly snapshot=/home/.snapshots/stateful-stack-p0-fixture-20260713
readonly archive=$evidence/source.tar.zst
readonly rollback='systemctl stop discovery-stateful-stack-fixture.service; retain all fixture evidence pending explicit cleanup approval'

die() {
  echo "stateful-stack-fixture: $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || die 'must run as root'
[ -d "$repository/.git" ] || die "repository missing: $repository"
for path in "$root" "$source_path" "$destination_path" "$plan" "$ledger" "$snapshot" "$archive" "${archive}.sha256"; do
  [ ! -e "$path" ] || die "fixture resource already exists: $path"
done
docker inspect "$container" >/dev/null 2>&1 && die "fixture container already exists: $container"

commit=$(git -C "$repository" rev-parse HEAD)
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die 'repository commit invalid'
image_id=$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null) || die "pinned fixture image absent: $image"
[ "$image_id" = 'sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d' ] ||
  die "fixture image identity mismatch: $image_id"

# This immutable record is written before creating the fixture source,
# destination, container, snapshot, or archive.
jq -n \
  --arg recorded_at "$(date --utc --iso-8601=seconds)" \
  --arg git_commit "$commit" \
  --arg container "$container" \
  --arg compose_owner '/etc/nixos/stateful-stack-p0-fixture' \
  --arg image_tag "$image" \
  --arg image_digest 'sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d' \
  --arg physical_volume "$source_path" \
  --arg mount '/fixture' \
  --arg snapshot_id "$snapshot" \
  --arg archive_id "$archive" \
  --arg rollback_command "$rollback" \
  '{version:1,$recorded_at,$git_commit,$container,compose_project:"p0-fixture",$compose_owner,$image_tag,$image_digest,physical_volume:$physical_volume,mount:$mount,size_bytes:0,ownership:"0:0",backup_snapshot:$snapshot_id,backup_archive:$archive_id,$rollback_command,expected_downtime:"none; disposable fixture only"}' \
  >"$plan"
chmod 0400 "$plan"

install -d -m 0700 -o root -g root "$source_path" "$destination_path"
printf '%s\n' 'stateful-stack-fixture-v1' >"$source_path/payload"
chmod 0640 "$source_path/payload"
setfacl -m u:65534:r "$source_path/payload"
setfattr -n user.stateful-stack-fixture -v p0 "$source_path/payload"

docker create \
  --name "$container" \
  --label com.docker.compose.project=p0-fixture \
  --label com.docker.compose.project.working_dir=/etc/nixos/stateful-stack-p0-fixture \
  --mount "type=bind,source=$source_path,target=/fixture" \
  --entrypoint /bin/sh \
  "$image" \
  -c 'while :; do sleep 3600; done' >/dev/null

discovery-stateful-stack-ops ledger-create \
  "$ledger" "$repository" "$container" /fixture /home "$snapshot" "$archive" \
  "$destination_path" "$rollback" 'none; disposable fixture only' >/dev/null
discovery-stateful-stack-ops snapshot "$ledger"
discovery-stateful-stack-ops archive "$ledger"
discovery-stateful-stack-ops restore "$ledger" "$destination_path"

docker start "$container" >/dev/null
discovery-stateful-stack-ops smoke "$ledger"
docker stop --time 10 "$container" >/dev/null
discovery-stateful-stack-ops rollback-evidence "$ledger"

jq -n \
  --arg git_commit "$commit" \
  --arg container "$container" \
  --arg image "$image" \
  --arg snapshot "$snapshot" \
  --arg archive "$archive" \
  --arg ledger "$ledger" \
  '{result:"passed",$git_commit,$container,$image,$snapshot,$archive,$ledger,resources_retained:true}'
