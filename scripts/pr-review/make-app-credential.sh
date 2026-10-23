#!/usr/bin/env bash
# Build the GitHub App credential JSON without printing the private key.
#
# Usage:
#   make-app-credential.sh --from-secrets <secrets.json> [out.json]
#   make-app-credential.sh <app-id> <installation-id> <private-key.pem> [out.json]
#
# --from-secrets expects app_id, installation_id, and private_key keys.
# A client_secret alone is not an installation credential and is rejected.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  make-app-credential.sh --from-secrets <secrets.json> [out.json]
  make-app-credential.sh <app-id> <installation-id> <private-key.pem> [out.json]
EOF
  exit 2
}

check_key() {
  local key_file=$1
  local tmp
  tmp=$(mktemp)
  chmod 600 "$tmp"
  trap 'rm -f "$tmp"' RETURN
  cp "$key_file" "$tmp"
  openssl pkey -in "$tmp" -noout >/dev/null 2>&1
}

report() {
  local out=$1
  local src=$2
  printf 'wrote %s (mode 600)\n' "$out"
  printf 'store it with:\n'
  printf '  bao kv patch secret/home/hermes GH_REVIEW_APP_JSON=@%s\n' "$out"
  printf 'then remove the local copy and the handoff:\n'
  printf '  shred -u %s %s\n' "$out" "$src"
}

if [ "${1:-}" = "--from-secrets" ]; then
  [ "$#" -ge 2 ] || usage
  src=$2
  out=${3:-hermes-review-app.json}
  test -s "$src" || { echo "missing secrets file: $src" >&2; exit 1; }
  if ! jq -e \
    '.app_id and (.installation_id|tostring|length>0) and (.private_key|length>0)' \
    "$src" >/dev/null 2>&1; then
    echo "missing app_id, installation_id, or private_key in $src" >&2
    echo "client_secret is not an installation credential; add the App private key." >&2
    exit 1
  fi
  umask 077
  jq '{app_id:(.app_id|tostring),installation_id:(.installation_id|tostring),private_key}' \
    "$src" >"$out"
  chmod 600 "$out"
  key_tmp=$(mktemp)
  chmod 600 "$key_tmp"
  jq -r '.private_key' "$out" >"$key_tmp"
  openssl pkey -in "$key_tmp" -noout >/dev/null 2>&1 || {
    rm -f "$key_tmp"
    echo "private_key is not a valid PEM key" >&2
    exit 1
  }
  rm -f "$key_tmp"
  report "$out" "$src"
  exit 0
fi

[ "$#" -ge 3 ] || usage
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
report "$out" "$key"
