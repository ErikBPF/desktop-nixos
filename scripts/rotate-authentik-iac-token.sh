#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo_root/scripts/authentik-admin-token.py
sops_file=${AUTHENTIK_SOPS_FILE:-$repo_root/secrets/sops/secrets.yaml}
[[ -f $sops_file ]] || { echo "Sops store missing" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
kubectl --context homelab -n authentik exec -i \
  deployment/authentik-worker -c worker -- \
  env AUTHENTIK_TOKEN_ACTION=rotate-iac ak shell <"$model" >"$tmp/response"
sed -n 's/^AUTHENTIK_IAC_TOKEN=//p' "$tmp/response" | tail -1 >"$tmp/payload"
jq -e 'type == "object" and keys == ["token"] and (.token | length >= 32)' \
  "$tmp/payload" >/dev/null

sops --decrypt --output "$tmp/plain.yaml" "$sops_file"
jq -j .token "$tmp/payload" >"$tmp/token"
chmod 600 "$tmp/token"
AUTHENTIK_IAC_TOKEN_FILE=$tmp/token
export AUTHENTIK_IAC_TOKEN_FILE
yq -i '.authentik_iac_token = load_str(strenv(AUTHENTIK_IAC_TOKEN_FILE))' \
  "$tmp/plain.yaml"
sops --encrypt --filename-override "$sops_file" \
  --output "$tmp/encrypted.yaml" "$tmp/plain.yaml"
grep -Fq 'sops:' "$tmp/encrypted.yaml"
install -m 0600 "$tmp/encrypted.yaml" "$sops_file"
echo "Authentik IaC token rotated into Sops"
