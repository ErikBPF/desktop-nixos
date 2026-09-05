#!/usr/bin/env bash
set -euo pipefail

check_only=false
if [[ ${1:-} == --check ]]; then
  check_only=true
  shift
fi
handoff=${1:-authentik-bootstrap.secrets.json}
[[ -f $handoff ]] || { echo "handoff missing" >&2; exit 1; }
[[ $(basename "$handoff") == authentik-bootstrap.secrets.json ]] || {
  echo "handoff must be named authentik-bootstrap.secrets.json" >&2
  exit 1
}
[[ $(stat -c '%a' "$handoff") == 600 ]] || {
  echo "handoff must have mode 0600" >&2
  exit 1
}
jq -e '
  type == "object" and
  (keys == ["bootstrap_token", "breakglass_password"]) and
  (.breakglass_password |
    type == "string" and length >= 20 and
    (explode | all(. >= 32 and . != 127))) and
  (.bootstrap_token |
    type == "string" and test("^[A-Za-z0-9._~-]{32,}$"))
' "$handoff" >/dev/null || { echo "handoff keys are invalid" >&2; exit 1; }

if $check_only; then
  echo "authentik bootstrap handoff OK"
  exit 0
fi

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sops_file=${AUTHENTIK_SOPS_FILE:-$repo_root/secrets/sops/secrets.yaml}
kube_context=${AUTHENTIK_KUBE_CONTEXT:-homelab}
[[ -f $sops_file ]] || { echo "Sops store missing" >&2; exit 1; }
kubectl --context "$kube_context" create namespace authentik \
  --dry-run=client -o yaml |
  kubectl --context "$kube_context" apply -f - >/dev/null
kubectl --context "$kube_context" label namespace authentik --overwrite \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest >/dev/null

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
chmod 700 "$tmp"
sops --decrypt --output "$tmp/plain.yaml" "$sops_file"

AUTHENTIK_PASSWORD_FILE=$tmp/password
AUTHENTIK_PASSWORD_HASH_FILE=$tmp/password-hash
AUTHENTIK_TOKEN_FILE=$tmp/token
jq -j .breakglass_password "$handoff" >"$AUTHENTIK_PASSWORD_FILE"
jq -j .bootstrap_token "$handoff" >"$AUTHENTIK_TOKEN_FILE"
chmod 600 "$AUTHENTIK_PASSWORD_FILE" "$AUTHENTIK_TOKEN_FILE"
python3 "$repo_root/scripts/authentik-password-hash.py" "$AUTHENTIK_PASSWORD_FILE" |
  tr -d '\n' >"$AUTHENTIK_PASSWORD_HASH_FILE"
chmod 600 "$AUTHENTIK_PASSWORD_HASH_FILE"
export AUTHENTIK_PASSWORD_FILE AUTHENTIK_PASSWORD_HASH_FILE AUTHENTIK_TOKEN_FILE
yq -i '
  .authentik_breakglass_password = load_str(strenv(AUTHENTIK_PASSWORD_FILE)) |
  .authentik_bootstrap_password_hash = load_str(strenv(AUTHENTIK_PASSWORD_HASH_FILE)) |
  .authentik_bootstrap_token = load_str(strenv(AUTHENTIK_TOKEN_FILE))
' "$tmp/plain.yaml"
sops --encrypt --filename-override "$sops_file" \
  --output "$tmp/encrypted.yaml" "$tmp/plain.yaml"
grep -Fq 'sops:' "$tmp/encrypted.yaml"
install -m 0600 "$tmp/encrypted.yaml" "$sops_file"

kubectl --context "$kube_context" -n authentik create secret generic authentik-bootstrap \
  --from-file=AUTHENTIK_BOOTSTRAP_PASSWORD_HASH="$AUTHENTIK_PASSWORD_HASH_FILE" \
  --from-file=AUTHENTIK_BOOTSTRAP_TOKEN="$AUTHENTIK_TOKEN_FILE" \
  --dry-run=client -o yaml |
  kubectl --context "$kube_context" -n authentik apply -f - >/dev/null

rm -f -- "$handoff"
echo "authentik bootstrap stored; handoff removed"
