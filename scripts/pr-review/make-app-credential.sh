#!/usr/bin/env bash
# Build the GitHub App credential JSON without printing the private key.
# Usage: make-app-credential.sh <app-id> <installation-id> <private-key.pem> [out.json]
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <app-id> <installation-id> <private-key.pem> [out.json]" >&2
  exit 2
fi

app_id=$1
installation_id=$2
key=$3
out=${4:-hermes-review-app.json}

test -s "$key" || { echo "missing private key: $key" >&2; exit 1; }
openssl pkey -in "$key" -noout >/dev/null 2>&1 || {
  echo "not a PEM private key: $key" >&2
  exit 1
}

umask 077
jq -n \
  --arg app_id "$app_id" \
  --arg installation_id "$installation_id" \
  --rawfile private_key "$key" \
  '{app_id:$app_id,installation_id:$installation_id,private_key:$private_key}' \
  >"$out"
chmod 600 "$out"

jq -e '.app_id and (.installation_id|tostring|length>0) and (.private_key|length>0)' \
  "$out" >/dev/null

printf 'wrote %s (mode 600)\n' "$out"
printf 'store it with:\n'
printf '  bao kv patch secret/home/hermes GH_REVIEW_APP_JSON=@%s\n' "$out"
printf 'then remove it:\n'
printf '  shred -u %s %s\n' "$out" "$key"
