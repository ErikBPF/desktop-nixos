#!/usr/bin/env bash
set -euo pipefail
umask 077

action=${1:-}
handoff=${2:-harbor-iam-provider.secrets.json}
discovery_ip=${3:-}
[[ $(basename "$handoff") == harbor-iam-provider.secrets.json ]] || {
  echo "handoff must be named harbor-iam-provider.secrets.json" >&2
  exit 64
}

validate() {
  local file=${1:-$handoff}
  [[ -f $file && $(stat -c '%a' "$file") == 600 ]] || {
    echo "handoff must exist with mode 0600" >&2
    exit 1
  }
  jq -e '
    type == "object" and
    keys == ["authentik_token", "harbor_password"] and
    (.authentik_token | type == "string" and length >= 32) and
    (.harbor_password | type == "string" and length > 0)
  ' "$file" >/dev/null
}

case $action in
  check)
    validate
    echo "Harbor IAM provider handoff OK"
    ;;
  create)
    [[ -n $discovery_ip ]] || { echo "discovery IP missing" >&2; exit 64; }
    [[ ! -e $handoff ]] || { echo "handoff already exists" >&2; exit 1; }
    handoff_dir=$(dirname "$handoff")
    git -C "$handoff_dir" check-ignore -q -- "$(basename "$handoff")" || {
      echo "handoff destination must be ignored" >&2
      exit 1
    }
    repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
    sops_file=${AUTHENTIK_SOPS_FILE:-$repo_root/secrets/sops/secrets.yaml}
    [[ -f $sops_file ]] || { echo "Sops store missing" >&2; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    sops --decrypt --extract '["authentik_iac_token"]' "$sops_file" \
      >"$tmp/authentik-token"
    [[ -s $tmp/authentik-token && $(awk 'END { print NR }' "$tmp/authentik-token") -eq 1 ]] || {
      echo "Authentik IaC token unavailable" >&2
      exit 1
    }
    ssh -p 2222 "erik@$discovery_ip" \
      "sudo sed -n 's/^HARBOR_ADMIN_PASSWORD=//p' /run/vault-agent/harbor.env" \
      >"$tmp/harbor-password"
    [[ -s $tmp/harbor-password && $(wc -l <"$tmp/harbor-password") -eq 1 ]] || {
      echo "Harbor admin password unavailable" >&2
      exit 1
    }
    jq -n \
      --rawfile authentik_token "$tmp/authentik-token" \
      --rawfile harbor_password "$tmp/harbor-password" \
      '{
        authentik_token: ($authentik_token | rtrimstr("\n")),
        harbor_password: ($harbor_password | rtrimstr("\n"))
      }' >"$tmp/handoff"
    validate "$tmp/handoff"
    install -m 0600 "$tmp/handoff" "$handoff"
    echo "Harbor IAM provider handoff created"
    ;;
  delete)
    rm -f -- "$handoff"
    echo "Harbor IAM provider handoff removed"
    ;;
  *)
    echo "usage: $0 {create|check|delete} [harbor-iam-provider.secrets.json] [discovery-ip]" >&2
    exit 64
    ;;
esac
