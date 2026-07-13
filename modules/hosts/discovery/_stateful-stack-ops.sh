# shellcheck shell=bash
set -euo pipefail
umask 077

die() {
  echo "stateful-stack-ops: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: discovery-stateful-stack-ops COMMAND ...

Read-only:
  inventory
  orphan-report
  read-verify LEDGER
  compare LEDGER DESTINATION
  smoke LEDGER [--expect-source source|destination] [--expect-image-ref REF] [--url URL] [--dns SERVER NAME] [--systemd UNIT]
  rollback-evidence LEDGER
  self-test

Mutating, ledger-gated (affected container must be stopped):
  ledger-create LEDGER REPOSITORY CONTAINER MOUNT_TARGET SNAPSHOT_SOURCE SNAPSHOT ARCHIVE COPY_DESTINATION ROLLBACK EXPECTED_DOWNTIME
  snapshot LEDGER
  archive LEDGER
  copy LEDGER DESTINATION
  restore LEDGER DESTINATION

No command deletes resources or executes rollback text.
EOF
  exit 2
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "must run as root"
}

absolute() {
  case "$1" in
    /*) ;;
    *) die "$2 must be an absolute path" ;;
  esac
}

load_ledger() {
  ledger=$1
  absolute "$ledger" "ledger"
  [ -f "$ledger" ] || die "ledger absent: $ledger"
  if find "$ledger" -maxdepth 0 -perm /077 -print -quit | grep -q .; then
    die "ledger permissions expose group/world access"
  fi
  jq -e '
    .version == 1 and
    ([.recorded_at, .git_commit, .container, .compose_project,
      .compose_owner, .image_tag, .image_digest, .volume_type,
      .physical_volume, .physical_source, .mount_target, .size_bytes,
      .ownership, .snapshot_source, .snapshot_id, .archive_id,
      .copy_destination, .rollback_command,
      .expected_downtime] | all(. != null and . != "")) and
    (.git_commit | test("^[0-9a-f]{40}$")) and
    (.image_digest | test("^sha256:[0-9a-f]{64}$")) and
    (.ownership | test("^[0-9]+:[0-9]+$")) and
    (.size_bytes | type == "number" and . >= 0)
  ' "$ledger" >/dev/null || die "ledger invalid or incomplete: $ledger"
}

field() {
  jq -er "$1" "$ledger"
}

assert_stopped() {
  local container running
  container=$(field '.container')
  docker inspect "$container" >/dev/null 2>&1 || die "container missing; stopped state ambiguous: $container"
  running=$(docker inspect --format '{{.State.Running}}' "$container")
  [ "$running" = false ] || die "container running: $container"
}

assert_source() {
  local source expected_owner actual_owner expected_size
  source=$(field '.physical_source')
  absolute "$source" "physical source"
  [ -d "$source" ] || die "physical source missing: $source"
  expected_owner=$(field '.ownership')
  actual_owner=$(stat -c '%u:%g' "$source")
  [ "$actual_owner" = "$expected_owner" ] ||
    die "ownership mismatch/ambiguity: ledger=$expected_owner actual=$actual_owner"
  expected_size=$(field '.size_bytes')
  [[ "$expected_size" =~ ^[0-9]+$ ]] || die "invalid recorded size"
}

assert_ledger_target() {
  local key=$1 actual=$2 expected
  expected=$(field "$key")
  [ "$actual" = "$expected" ] || die "target differs from ledger: expected=$expected actual=$actual"
}

inventory() {
  local container inspect containers mounts units
  containers=$(docker ps -a --no-trunc --format '{{json .}}' | jq -s .)
  mounts=$(
  while IFS= read -r container; do
    [ -n "$container" ] || continue
    inspect=$(docker inspect "$container")
    while IFS= read -r mount; do
      jq -cn --argjson m "$mount" --arg container "$container" \
        --arg project "$(jq -r '.[0].Config.Labels["com.docker.compose.project"] // ""' <<<"$inspect")" \
        --arg owner "$(jq -r '.[0].Config.Labels["com.docker.compose.project.working_dir"] // ""' <<<"$inspect")" \
        --argjson size "$(du -sb "$(jq -r '.Source' <<<"$mount")" 2>/dev/null | awk '{print $1}' || echo 0)" \
        --arg ownership "$(stat -c '%u:%g' "$(jq -r '.Source' <<<"$mount")" 2>/dev/null || echo unknown)" \
        '$m + {container:$container,compose_project:$project,compose_owner:$owner,size_bytes:$size,ownership:$ownership}'
    done < <(jq -c '.[0].Mounts[]' <<<"$inspect")
  done < <(docker ps -aq)
  )
  mounts=$(jq -s . <<<"$mounts")
  units=$(systemctl list-unit-files --type=service --no-legend --no-pager |
    awk '$1 ~ /(docker|compose|servarr)/ {print $1}' |
    jq -Rsc 'split("\n") | map(select(length > 0))')
  jq -n --argjson containers "$containers" --argjson mounts "$mounts" \
    --argjson declared_units "$units" \
    '{$containers,$mounts,$declared_units}'
}

orphan_report() {
  echo '{"volume_candidates":['
  local first=1 volume source size owner
  while IFS= read -r volume; do
    [ -n "$volume" ] || continue
    source=$(docker volume inspect --format '{{.Mountpoint}}' "$volume")
    size=$(du -sb "$source" 2>/dev/null | awk '{print $1}' || echo 0)
    owner=$(stat -c '%u:%g' "$source" 2>/dev/null || echo unknown)
    [ "$first" -eq 1 ] || echo ','
    first=0
    jq -cn --arg volume "$volume" --arg source "$source" \
      --argjson size "$size" --arg ownership "$owner" \
      '{volume:$volume,source:$source,size_bytes:$size,ownership:$ownership,classification:"candidate-only; verify backup and unique state"}'
  done < <(docker volume ls -qf dangling=true)
  echo ']}'
}

ledger_create() {
  [ "$#" -eq 10 ] || usage
  local out=$1 repo=$2 container=$3 target=$4 snapshot_source=$5 snapshot=$6 archive=$7 copy_destination=$8 rollback=$9 downtime=${10}
  local inspect image_inspect matches mount source commit project owner image_tag digest_count digest volume_type physical_volume size ownership tmp
  absolute "$out" "ledger"
  absolute "$repo" "repository"
  absolute "$snapshot_source" "snapshot source"
  absolute "$snapshot" "snapshot"
  absolute "$archive" "archive"
  absolute "$copy_destination" "copy destination"
  [ ! -e "$out" ] || die "ledger already exists: $out"
  [ -d "$repo/.git" ] || die "repository missing .git: $repo"
  [[ "$target" = /* ]] || die "mount target must be absolute"
  [ -n "$rollback" ] || die "rollback command absent"
  [ -n "$downtime" ] || die "expected downtime absent"
  inspect=$(docker inspect "$container" 2>/dev/null) || die "container missing: $container"
  project=$(jq -er '.[0].Config.Labels["com.docker.compose.project"] | select(length > 0)' <<<"$inspect") || die "Compose project label absent"
  owner=$(jq -er '.[0].Config.Labels["com.docker.compose.project.working_dir"] | select(length > 0)' <<<"$inspect") || die "Compose owner label absent"
  matches=$(jq --arg target "$target" '[.[0].Mounts[] | select(.Destination == $target)] | length' <<<"$inspect")
  [ "$matches" -eq 1 ] || die "mount ownership ambiguous: found $matches mounts for $target"
  mount=$(jq -c --arg target "$target" '.[0].Mounts[] | select(.Destination == $target)' <<<"$inspect")
  source=$(jq -er '.Source' <<<"$mount")
  [ -d "$source" ] || die "mount source missing: $source"
  [ -d "$snapshot_source" ] || die "snapshot source missing: $snapshot_source"
  # Named volumes are protected by archive_id. snapshot_source independently
  # covers bind-mounted state and therefore need not contain physical_source.
  btrfs subvolume show "$snapshot_source" >/dev/null 2>&1 || die "snapshot source is not a Btrfs subvolume"
  commit=$(git -c "safe.directory=$repo" -C "$repo" rev-parse HEAD)
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "Git commit invalid"
  image_tag=$(jq -er '.[0].Config.Image | select(length > 0)' <<<"$inspect")
  image_inspect=$(docker image inspect "$(jq -er '.[0].Image' <<<"$inspect")") || die "container image missing"
  digest_count=$(jq '[.[0].RepoDigests[]? | split("@")[-1]] | unique | length' <<<"$image_inspect")
  [ "$digest_count" -eq 1 ] || die "image digest absent or ambiguous"
  digest=$(jq -er '[.[0].RepoDigests[] | split("@")[-1]] | unique[0] | select(test("^sha256:[0-9a-f]{64}$"))' <<<"$image_inspect") || die "image digest invalid"
  volume_type=$(jq -er '.Type' <<<"$mount")
  physical_volume=$(jq -r 'if .Type == "volume" then .Name else .Source end' <<<"$mount")
  size=$(du -sb "$source" | awk '{print $1}')
  ownership=$(stat -c '%u:%g' "$source")
  mkdir -p "$(dirname "$out")"
  tmp=$(mktemp "${out}.tmp.XXXXXX")
  trap 'rm -f "$tmp"' RETURN
  jq -n \
    --arg recorded_at "$(date --utc --iso-8601=seconds)" --arg git_commit "$commit" \
    --arg container "$container" --arg compose_project "$project" --arg compose_owner "$owner" \
    --arg image_tag "$image_tag" --arg image_digest "$digest" --arg volume_type "$volume_type" \
    --arg physical_volume "$physical_volume" --arg physical_source "$source" --arg mount_target "$target" \
    --argjson size_bytes "$size" --arg ownership "$ownership" --arg snapshot_source "$snapshot_source" \
    --arg snapshot_id "$snapshot" --arg archive_id "$archive" --arg copy_destination "$copy_destination" \
    --arg rollback_command "$rollback" --arg expected_downtime "$downtime" \
    '{version:1,$recorded_at,$git_commit,$container,$compose_project,$compose_owner,$image_tag,$image_digest,$volume_type,$physical_volume,$physical_source,$mount_target,$size_bytes,$ownership,$snapshot_source,$snapshot_id,$archive_id,$copy_destination,$rollback_command,$expected_downtime}' \
    >"$tmp"
  chmod 0600 "$tmp"
  mv -n "$tmp" "$out" || die "could not atomically create ledger"
  trap - RETURN
  echo "$out"
}

snapshot_volume() {
  load_ledger "$1"
  assert_stopped
  assert_source
  local source snapshot
  source=$(field '.snapshot_source')
  snapshot=$(field '.snapshot_id')
  absolute "$snapshot" "snapshot"
  [ ! -e "$snapshot" ] || die "snapshot already exists: $snapshot"
  btrfs subvolume show "$source" >/dev/null 2>&1 || die "source is not a Btrfs subvolume: $source"
  btrfs subvolume snapshot -r "$source" "$snapshot"
  btrfs subvolume show "$snapshot" >/dev/null || die "snapshot verification failed"
}

archive_volume() {
  load_ledger "$1"
  assert_stopped
  assert_source
  local source archive checksum
  source=$(field '.physical_source')
  archive=$(field '.archive_id')
  absolute "$archive" "archive"
  [ ! -e "$archive" ] && [ ! -e "${archive}.sha256" ] || die "archive or checksum already exists"
  mkdir -p "$(dirname "$archive")"
  tar --acls --xattrs --xattrs-include='*' --numeric-owner --one-file-system -C "$source" -I zstd -cf "$archive" .
  checksum=$(sha256sum "$archive")
  printf '%s\n' "$checksum" >"${archive}.sha256"
  read_verify "$1"
}

read_verify() {
  load_ledger "$1"
  local archive
  archive=$(field '.archive_id')
  [ -f "$archive" ] || die "backup missing: $archive"
  [ -f "${archive}.sha256" ] || die "backup checksum missing: ${archive}.sha256"
  (cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive").sha256") >/dev/null || die "checksum mismatch"
  tar -I zstd -tf "$archive" >/dev/null || die "archive list/read verification failed"
  zstd --test "$archive" >/dev/null || die "archive stream verification failed"
  echo "verified $archive"
}

copy_volume() {
  [ "$#" -eq 2 ] || usage
  load_ledger "$1"
  assert_stopped
  assert_source
  read_verify "$1"
  local source destination=$2
  source=$(field '.physical_source')
  absolute "$destination" "destination"
  assert_ledger_target '.copy_destination' "$destination"
  [ -d "$destination" ] || die "destination missing: $destination"
  [ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ] || die "destination not empty"
  tar --acls --xattrs --xattrs-include='*' --numeric-owner -C "$source" -cf - . |
    tar --acls --xattrs --xattrs-include='*' --numeric-owner --same-owner --same-permissions -C "$destination" -xf -
  compare_volume "$1" "$destination"
}

restore_volume() {
  [ "$#" -eq 2 ] || usage
  load_ledger "$1"
  assert_stopped
  assert_source
  read_verify "$1"
  local archive destination=$2
  archive=$(field '.archive_id')
  absolute "$destination" "destination"
  assert_ledger_target '.copy_destination' "$destination"
  [ -d "$destination" ] || die "destination missing: $destination"
  [ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ] || die "destination not empty"
  tar --acls --xattrs --xattrs-include='*' --numeric-owner --same-owner --same-permissions \
    -C "$destination" -I zstd -xf "$archive"
  compare_volume "$1" "$destination"
}

compare_volume() {
  [ "$#" -eq 2 ] || usage
  load_ledger "$1"
  assert_stopped
  assert_source
  local source destination delta
  source=$(field '.physical_source')
  destination=$2
  absolute "$destination" "destination"
  assert_ledger_target '.copy_destination' "$destination"
  [ -d "$destination" ] || die "destination missing: $destination"
  delta=$(rsync -aHAXnc --delete --numeric-ids --itemize-changes -- "$source/" "$destination/")
  [ -z "$delta" ] || die "source/destination differ: $delta"
  [ "$(stat -c '%u:%g' "$source")" = "$(stat -c '%u:%g' "$destination")" ] || die "destination root ownership differs"
  echo "match $source $destination"
}

assert_live_identity() {
  local expected_source=${1:-} expected_image_ref=${2:-} container inspect image_inspect target matches current_digest health
  [ -n "$expected_source" ] || expected_source=$(field '.physical_source')
  [ -n "$expected_image_ref" ] || expected_image_ref=$(field '.image_tag')
  container=$(field '.container')
  inspect=$(docker inspect "$container" 2>/dev/null) || die "container missing: $container"
  [ "$(jq -r '.[0].State.Running' <<<"$inspect")" = true ] || die "container not running: $container"
  [ "$(jq -r '.[0].Config.Labels["com.docker.compose.project"] // ""' <<<"$inspect")" = "$(field '.compose_project')" ] ||
    die "Compose project differs from ledger"
  [ "$(jq -r '.[0].Config.Labels["com.docker.compose.project.working_dir"] // ""' <<<"$inspect")" = "$(field '.compose_owner')" ] ||
    die "Compose owner differs from ledger"
  [ "$(jq -r '.[0].Config.Image' <<<"$inspect")" = "$expected_image_ref" ] || die "image ref differs from expected"
  image_inspect=$(docker image inspect "$(jq -er '.[0].Image' <<<"$inspect")") || die "container image missing"
  current_digest=$(jq -er '[.[0].RepoDigests[]? | split("@")[-1]] | unique | if length == 1 then .[0] else empty end' <<<"$image_inspect") ||
    die "live image digest absent or ambiguous"
  [ "$current_digest" = "$(field '.image_digest')" ] || die "live image digest differs from ledger"
  target=$(field '.mount_target')
  matches=$(jq --arg target "$target" --arg source "$expected_source" \
    '[.[0].Mounts[] | select(.Destination == $target and .Source == $source)] | length' <<<"$inspect")
  [ "$matches" -eq 1 ] || die "live physical mount differs from ledger"
  health=$(jq -r '.[0].State.Health.Status // "undefined"' <<<"$inspect")
  [ "$health" = undefined ] || [ "$health" = healthy ] || die "container health is $health"
  [ "$(jq -r '.[0].RestartCount' <<<"$inspect")" -eq 0 ] || die "container restart count nonzero"
}

smoke() {
  [ "$#" -ge 1 ] || usage
  load_ledger "$1"
  shift
  local container expected_source expected_image_ref
  container=$(field '.container')
  expected_source=$(field '.physical_source')
  expected_image_ref=$(field '.image_tag')
  if [ "${1:-}" = --expect-source ]; then
    [ "$#" -ge 2 ] || usage
    case "$2" in
      source) ;;
      destination) expected_source=$(field '.copy_destination') ;;
      *) die "expected source must be source or destination" ;;
    esac
    shift 2
  fi
  if [ "${1:-}" = --expect-image-ref ]; then
    [ "$#" -ge 2 ] || usage
    expected_image_ref=$2
    [ -n "$expected_image_ref" ] || die "expected image ref must not be empty"
    shift 2
  fi
  assert_live_identity "$expected_source" "$expected_image_ref"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --url) [ "$#" -ge 2 ] || usage; curl --fail --silent --show-error --location --max-time 15 "$2" >/dev/null; shift 2 ;;
      --dns) [ "$#" -ge 3 ] || usage; dig +time=3 +tries=1 +short "@$2" "$3" | grep -q . || die "DNS probe failed: $2 $3"; shift 3 ;;
      --systemd) [ "$#" -ge 2 ] || usage; systemctl is-active --quiet "$2" || die "systemd unit inactive: $2"; shift 2 ;;
      *) die "unsupported smoke argument: $1" ;;
    esac
  done
  echo "smoke passed: $container"
}

rollback_evidence() {
  load_ledger "$1"
  assert_source
  read_verify "$1"
  local snapshot
  snapshot=$(field '.snapshot_id')
  [ -e "$snapshot" ] || die "snapshot missing: $snapshot"
  echo "container=$(field '.container')"
  echo "image=$(field '.image_tag')@$(field '.image_digest')"
  echo "snapshot=$snapshot"
  echo "archive=$(field '.archive_id')"
  echo "rollback_command=$(field '.rollback_command')"
  echo "rollback_not_executed=true"
}

self_test() {
  local dep
  for dep in btrfs curl dig docker find git jq rsync sha256sum stat systemctl tar zstd; do
    command -v "$dep" >/dev/null || die "dependency missing: $dep"
  done
  if jq -e '.version == 1' /dev/null >/dev/null 2>&1; then
    die "invalid-ledger guard failed"
  fi
  echo "self-test passed: dependencies and fail-closed ledger parser available"
}

require_root
command=${1:-}
[ -n "$command" ] || usage
shift
case "$command" in
  inventory) [ "$#" -eq 0 ] || usage; inventory ;;
  orphan-report) [ "$#" -eq 0 ] || usage; orphan_report ;;
  ledger-create) ledger_create "$@" ;;
  snapshot) [ "$#" -eq 1 ] || usage; snapshot_volume "$1" ;;
  archive) [ "$#" -eq 1 ] || usage; archive_volume "$1" ;;
  read-verify) [ "$#" -eq 1 ] || usage; read_verify "$1" ;;
  copy) copy_volume "$@" ;;
  restore) restore_volume "$@" ;;
  compare) compare_volume "$@" ;;
  smoke) smoke "$@" ;;
  rollback-evidence) [ "$#" -eq 1 ] || usage; rollback_evidence "$1" ;;
  self-test) [ "$#" -eq 0 ] || usage; self_test ;;
  *) usage ;;
esac
