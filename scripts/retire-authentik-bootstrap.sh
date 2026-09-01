#!/usr/bin/env bash
set -euo pipefail

check_only=false
if [[ ${1:-} == --check ]]; then
  check_only=true
  shift
fi
handoff=${1:-authentik-iac.secrets.json}
[[ -f $handoff ]] || { echo "handoff missing" >&2; exit 1; }
[[ $(basename "$handoff") == authentik-iac.secrets.json ]] || {
  echo "handoff must be named authentik-iac.secrets.json" >&2
  exit 1
}
[[ $(stat -c '%a' "$handoff") == 600 ]] || {
  echo "handoff must have mode 0600" >&2
  exit 1
}
jq -e '
  type == "object" and
  (keys == ["token", "username"]) and
  (.username == "svc-homelab-iac-authentik-config-manager") and
  (.token | type == "string" and length >= 32)
' "$handoff" >/dev/null || { echo "handoff keys are invalid" >&2; exit 1; }

if $check_only; then
  echo "authentik retirement handoff OK"
  exit 0
fi

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sops_file=${AUTHENTIK_SOPS_FILE:-$repo_root/secrets/sops/secrets.yaml}
kube_context=${AUTHENTIK_KUBE_CONTEXT:-homelab}
api_base=${AUTHENTIK_API_BASE:-https://authentik.homelab.pastelariadev.com/api/v3}
[[ -f $sops_file ]] || { echo "Sops store missing" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
chmod 700 "$tmp"
sops --decrypt --output "$tmp/plain.yaml" "$sops_file"
yq -e '.authentik_bootstrap_token and .authentik_bootstrap_password_hash' \
  "$tmp/plain.yaml" >/dev/null || { echo "bootstrap material missing" >&2; exit 1; }

AUTHENTIK_IAC_TOKEN_FILE=$tmp/iac-token
AUTHENTIK_BOOTSTRAP_HEADER_FILE=$tmp/bootstrap-header
jq -j .token "$handoff" >"$AUTHENTIK_IAC_TOKEN_FILE"
yq -r '.authentik_bootstrap_token' "$tmp/plain.yaml" |
  sed 's/^/Authorization: Bearer /' >"$AUTHENTIK_BOOTSTRAP_HEADER_FILE"
chmod 600 "$AUTHENTIK_IAC_TOKEN_FILE" "$AUTHENTIK_BOOTSTRAP_HEADER_FILE"

export AUTHENTIK_IAC_TOKEN_FILE
yq -i '
  .authentik_iac_token = load_str(strenv(AUTHENTIK_IAC_TOKEN_FILE)) |
  del(.authentik_bootstrap_token) |
  del(.authentik_bootstrap_password_hash)
' "$tmp/plain.yaml"
sops --encrypt --filename-override "$sops_file" \
  --output "$tmp/encrypted.yaml" "$tmp/plain.yaml"
grep -Fq 'sops:' "$tmp/encrypted.yaml"

code=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --request DELETE --header @"$AUTHENTIK_BOOTSTRAP_HEADER_FILE" \
  "$api_base/core/tokens/authentik-bootstrap-token/")
[[ $code == 204 ]] || { echo "bootstrap token revocation failed ($code)" >&2; exit 1; }

install -m 0600 "$tmp/encrypted.yaml" "$sops_file"
kubectl --context "$kube_context" -n authentik \
  delete secret authentik-bootstrap --ignore-not-found >/dev/null
rm -f -- "$handoff"
echo "authentik bootstrap retired; IaC token stored; handoff removed"
