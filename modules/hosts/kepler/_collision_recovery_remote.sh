#!/usr/bin/env bash
# Read-only remote-side sanitizer. Raw Podman inspect data never crosses stdout.
set -euo pipefail

sanitize() {
  local datasets="$1" images="$2" volumes="$3" networks="$4" snapshots="$5"
  jq -c --arg datasets "$datasets" --argjson images "$images" --argjson volumes "$volumes" --argjson networks "$networks" --arg snapshots "$snapshots" '
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
        images: ($images | map({id: (.Id // ""), digests: (.RepoDigests // []), names: (.RepoTags // [])})),
        volumes: ($volumes | map({name: (.Name // ""), driver: (.Driver // ""), mountpoint: (.Mountpoint // ""), labels: (.Labels // {})})),
        networks: ($networks | map({id: (.Id // ""), name: (.Name // ""), driver: (.Driver // ""), labels: (.Labels // {})})),
        snapshots: ($snapshots | split("\n") | map(select(length > 0)) | map({name: .}))
      }
  '
}

if [[ ${1:-} == "--fixture" ]]; then
  [[ $# == 7 ]] || { echo "usage: $0 --fixture CONTAINERS DATASETS IMAGES VOLUMES NETWORKS SNAPSHOTS" >&2; exit 2; }
  sanitize "$(<"$3")" "$(<"$4")" "$(<"$5")" "$(<"$6")" "$(<"$7")" <"$2"
  exit
fi
[[ $# == 0 ]] || { echo "usage: $0 [--fixture INSPECT_JSON ZFS_TSV]" >&2; exit 2; }

mapfile -t ids < <(podman ps --all --quiet --no-trunc)
for id in "${ids[@]}"; do
  [[ $id =~ ^[0-9a-f]{64}$ ]] || { echo "inventory halted: invalid container ID" >&2; exit 1; }
done
datasets=$(zfs list -H -o name,mountpoint)
snapshots=$(zfs list -H -t snapshot -o name)
mapfile -t image_ids < <(podman image list --quiet --no-trunc)
images=$(if ((${#image_ids[@]})); then podman image inspect "${image_ids[@]}"; else printf '[]\n'; fi)
mapfile -t volume_names < <(podman volume list --quiet)
volumes=$(if ((${#volume_names[@]})); then podman volume inspect "${volume_names[@]}"; else printf '[]\n'; fi)
mapfile -t network_ids < <(podman network list --quiet --no-trunc)
networks=$(if ((${#network_ids[@]})); then podman network inspect "${network_ids[@]}"; else printf '[]\n'; fi)
if ((${#ids[@]})); then
  podman container inspect "${ids[@]}" | sanitize "$datasets" "$images" "$volumes" "$networks" "$snapshots"
else
  printf '[]\n' | sanitize "$datasets" "$images" "$volumes" "$networks" "$snapshots"
fi
