#!/usr/bin/env bash
set -euo pipefail
umask 077

action=${1:-}
handoff=${2:-authentik-admin-token.secrets.json}
[[ $(basename "$handoff") == authentik-admin-token.secrets.json ]] || {
  echo "handoff must be named authentik-admin-token.secrets.json" >&2
  exit 64
}

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo_root/scripts/authentik-admin-token.py

if [[ $action == check ]]; then
  [[ -f $handoff && $(stat -c '%a' "$handoff") == 600 ]] || {
    echo "handoff must exist with mode 0600" >&2
    exit 1
  }
  jq -e 'type == "object" and keys == ["token"] and (.token | length >= 32)' \
    "$handoff" >/dev/null
  echo "authentik admin token handoff OK"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
response=$tmp/response
payload=$tmp/payload

case $action in
  create)
    [[ ! -e $handoff ]] || { echo "handoff already exists" >&2; exit 1; }
    kubectl --context homelab -n authentik exec -i \
      deployment/authentik-worker -c worker -- \
      env AUTHENTIK_TOKEN_ACTION=create ak shell <"$model" >"$response"
    sed -n 's/^AUTHENTIK_ADMIN_TOKEN=//p' "$response" | tail -1 >"$payload"
    jq -e 'type == "object" and keys == ["token"] and (.token | length >= 32)' \
      "$payload" >/dev/null
    install -m 0600 "$payload" "$handoff"
    echo "authentik temporary admin token stored in handoff"
    ;;
  revoke)
    kubectl --context homelab -n authentik exec -i \
      deployment/authentik-worker -c worker -- \
      env AUTHENTIK_TOKEN_ACTION=revoke ak shell <"$model" >"$response"
    sed -n 's/^AUTHENTIK_ADMIN_TOKEN=//p' "$response" | tail -1 >"$payload"
    jq -e '.revoked == true' "$payload" >/dev/null
    rm -f -- "$handoff"
    echo "authentik temporary admin token revoked; handoff removed"
    ;;
  *)
    echo "usage: $0 {create|check|revoke} [authentik-admin-token.secrets.json]" >&2
    exit 64
    ;;
esac
