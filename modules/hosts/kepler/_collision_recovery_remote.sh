#!/usr/bin/env bash
# Read-only remote-side sanitizer. Raw Podman inspect data never crosses stdout.
set -euo pipefail

sanitize() {
  local datasets="$1"
  jq -c --arg datasets "$datasets" '
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
        ))
      }
  '
}

if [[ ${1:-} == "--fixture" ]]; then
  [[ $# == 3 ]] || { echo "usage: $0 --fixture INSPECT_JSON ZFS_TSV" >&2; exit 2; }
  sanitize "$(<"$3")" <"$2"
  exit
fi
[[ $# == 0 ]] || { echo "usage: $0 [--fixture INSPECT_JSON ZFS_TSV]" >&2; exit 2; }

mapfile -t ids < <(podman ps --all --quiet --no-trunc)
for id in "${ids[@]}"; do
  [[ $id =~ ^[0-9a-f]{64}$ ]] || { echo "inventory halted: invalid container ID" >&2; exit 1; }
done
datasets=$(zfs list -H -o name,mountpoint)
if ((${#ids[@]})); then
  podman container inspect "${ids[@]}" | sanitize "$datasets"
else
  printf '[]\n' | sanitize "$datasets"
fi
