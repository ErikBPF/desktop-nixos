#!/usr/bin/env bash
# Read-only remote-side sanitizer. Raw Podman inspect data never crosses stdout.
set -euo pipefail

sanitize() {
  local datasets_file="$1" images_file="$2" volumes_file="$3" networks_file="$4" snapshots_file="$5"
  jq -c --rawfile datasets "$datasets_file" --slurpfile images "$images_file" \
    --slurpfile volumes "$volumes_file" --slurpfile networks "$networks_file" \
    --rawfile snapshots "$snapshots_file" '
    if type != "array" then error("inspect response must be an array") else . end
    | {
        containers: map({
          Id: (.Id // ""),
          Image: (.Image // ""),
          ImageName: (.Config.Image // ""),
          ImageDigest: (.ImageDigest // ""),
          Labels: (.Config.Labels // {}),
          Mounts: ((.Mounts // []) | map({
            Source: (.Source // ""),
            Destination: (.Destination // ""),
            Name: (.Name // "")
          })),
          Name: (.Name // ""),
          Networks: ((.NetworkSettings.Networks // {}) | keys),
          State: (.State.Status // "")
        }),
        datasets: ($datasets | split("\n") | map(select(length > 0)) | map(
          split("\t") | if length == 2 then {name: .[0], mountpoint: .[1]}
          else error("malformed zfs row") end
        )),
        images: (($images | add // []) | map({id: (.Id // ""), digests: (.RepoDigests // []), names: (.RepoTags // [])})),
        volumes: (($volumes | add // []) | map({name: (.Name // ""), driver: (.Driver // ""), mountpoint: (.Mountpoint // ""), labels: (.Labels // {})})),
        networks: (($networks | add // []) | map({id: (.Id // ""), name: (.Name // ""), driver: (.Driver // ""), labels: (.Labels // {})})),
        snapshots: ($snapshots | split("\n") | map(select(length > 0)) | map({name: .}))
      }
  '
}

if [[ ${1:-} == "--fixture" ]]; then
  [[ $# == 7 ]] || { echo "usage: $0 --fixture CONTAINERS DATASETS IMAGES VOLUMES NETWORKS SNAPSHOTS" >&2; exit 2; }
  sanitize "$3" "$4" "$5" "$6" "$7" <"$2"
  exit
fi
[[ $# == 0 ]] || { echo "usage: $0 [--fixture INSPECT_JSON ZFS_TSV]" >&2; exit 2; }

mapfile -t ids < <(podman ps --all --quiet --no-trunc)
for id in "${ids[@]}"; do
  [[ $id =~ ^[0-9a-f]{64}$ ]] || { echo "inventory halted: invalid container ID" >&2; exit 1; }
done
mapfile -t image_ids < <(podman image list --quiet --no-trunc)
mapfile -t volume_names < <(podman volume list --quiet)
mapfile -t network_ids < <(podman network list --quiet --no-trunc)
if ((${#ids[@]})); then
  podman container inspect "${ids[@]}" | sanitize \
    <(zfs list -H -o name,mountpoint) \
    <(if ((${#image_ids[@]})); then podman image inspect "${image_ids[@]}"; else printf '[]\n'; fi) \
    <(if ((${#volume_names[@]})); then podman volume inspect "${volume_names[@]}"; else printf '[]\n'; fi) \
    <(if ((${#network_ids[@]})); then podman network inspect "${network_ids[@]}"; else printf '[]\n'; fi) \
    <(zfs list -H -t snapshot -o name)
else
  printf '[]\n' | sanitize \
    <(zfs list -H -o name,mountpoint) \
    <(if ((${#image_ids[@]})); then podman image inspect "${image_ids[@]}"; else printf '[]\n'; fi) \
    <(if ((${#volume_names[@]})); then podman volume inspect "${volume_names[@]}"; else printf '[]\n'; fi) \
    <(if ((${#network_ids[@]})); then podman network inspect "${network_ids[@]}"; else printf '[]\n'; fi) \
    <(zfs list -H -t snapshot -o name)
fi
