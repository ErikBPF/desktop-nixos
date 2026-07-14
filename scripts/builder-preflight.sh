#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: builder-preflight.sh '<nix builders specification>'" >&2
}

if [[ $# -ne 1 || -z ${1//[[:space:]]/} ]]; then
  usage
  exit 2
fi

IFS=';' read -r -a builders <<<"$1"
failed=0

for builder in "${builders[@]}"; do
  builder="${builder#"${builder%%[![:space:]]*}"}"
  builder="${builder%"${builder##*[![:space:]]}"}"
  read -r uri _systems ssh_key _rest <<<"$builder"

  if [[ $uri != ssh-ng://* ]]; then
    echo "FAIL malformed builder: expected ssh-ng:// endpoint" >&2
    failed=1
    continue
  fi
  if [[ ! $uri =~ ^ssh-ng://[^/@[:space:]]+@([^/:[:space:]]+):([0-9]+)$ ]]; then
    echo "FAIL ${uri#ssh-ng://}: explicit port required" >&2
    failed=1
    continue
  fi

  endpoint="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
  store_uri=$uri
  if [[ -n ${ssh_key:-} && $ssh_key != - ]]; then
    store_uri+="?ssh-key=$ssh_key"
  fi

  if timeout 10 nix store ping --store "$store_uri" >/dev/null 2>&1; then
    echo "OK $endpoint"
  else
    echo "FAIL $endpoint — check SSH, builder key, and nix-daemon" >&2
    failed=1
  fi
done

exit "$failed"
