#!/usr/bin/env bash
set -euo pipefail

url=https://harbor.homelab.pastelariadev.com
env_file=/run/vault-agent/harbor.env
while (($#)); do
  case "$1" in
    --url) url=$2; shift 2 ;;
    --env-file) env_file=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

tool() {
  if [[ -x /run/current-system/sw/bin/$1 ]]; then
    printf '%s\n' "/run/current-system/sw/bin/$1"
  else
    command -v "$1"
  fi
}

curl_bin=$(tool curl)
jq_bin=$(tool jq)
base64_bin=$(tool base64)
sed_bin=$(tool sed)
mktemp_bin=$(tool mktemp)
chmod_bin=$(tool chmod)
cat_bin=$(tool cat)
rm_bin=$(tool rm)

admin_user=$($sed_bin -n 's/^HARBOR_ADMIN_USER=//p' "$env_file")
admin_password=$($sed_bin -n 's/^HARBOR_ADMIN_PASSWORD=//p' "$env_file")
admin_user=${admin_user:-admin}
for quote in '"' "'"; do
  admin_user=${admin_user#"$quote"}; admin_user=${admin_user%"$quote"}
  admin_password=${admin_password#"$quote"}; admin_password=${admin_password%"$quote"}
done
[[ -n $admin_password ]] || { echo "HARBOR_ADMIN_PASSWORD missing" >&2; exit 1; }

tmp=$($mktemp_bin -d)
trap '$rm_bin -rf -- "$tmp"' EXIT
$chmod_bin 700 "$tmp"
auth=$(printf '%s' "$admin_user:$admin_password" | "$base64_bin" -w0)
printf 'header = "Authorization: Basic %s"\n' "$auth" >"$tmp/curl.conf"
$chmod_bin 600 "$tmp/curl.conf"
unset admin_password auth

fetch() {
  local endpoint=$1 output=$2
  "$curl_bin" --fail --silent --show-error --max-time 15 \
    --config "$tmp/curl.conf" "$url$endpoint" --output "$output"
}

fetch /api/v2.0/systeminfo "$tmp/system.json"
fetch /api/v2.0/configurations "$tmp/configuration.json"
fetch '/api/v2.0/users?page_size=100' "$tmp/users.json"
fetch '/api/v2.0/projects?page_size=100' "$tmp/projects.json"
fetch '/api/v2.0/robots?page_size=100' "$tmp/robots.json"

: >"$tmp/user-details.ndjson"
while IFS= read -r user_id; do
  if ! response=$("$curl_bin" --silent --show-error --max-time 15 \
    --config "$tmp/curl.conf" --write-out $'\n%{http_code}' \
    "$url/api/v2.0/users/$user_id"); then
    echo "failed to inspect Harbor user $user_id" >&2
    exit 1
  fi
  status=${response##*$'\n'}
  body=${response%$'\n'*}
  case "$status" in
    200)
      printf '%s' "$body" | "$jq_bin" -c \
        '{user_id, oidc: (.oidc_user_meta != null)}' \
        >>"$tmp/user-details.ndjson"
      ;;
    404)
      # shellcheck disable=SC2016 # $user_id is a jq variable.
      "$jq_bin" -cn --argjson user_id "$user_id" \
        '{user_id: $user_id, oidc: false}' >>"$tmp/user-details.ndjson"
      ;;
    *)
      echo "Harbor user detail returned HTTP $status for user $user_id" >&2
      exit 1
      ;;
  esac
  unset response body status
done < <("$jq_bin" -r '.[] | select((.sysadmin_flag // false) == false) | .user_id' \
  "$tmp/users.json")
"$jq_bin" -s . "$tmp/user-details.ndjson" >"$tmp/user-details.json"

# The single-quoted jq program intentionally expands inside jq, not Bash.
# shellcheck disable=SC2016
"$jq_bin" -n \
  --slurpfile system "$tmp/system.json" \
  --slurpfile configuration "$tmp/configuration.json" \
  --slurpfile users "$tmp/users.json" \
  --slurpfile user_details "$tmp/user-details.json" \
  --slurpfile projects "$tmp/projects.json" \
  --slurpfile robots "$tmp/robots.json" '
    def value($object; $key):
      ($object[$key] // null) as $value |
      if ($value | type) == "object" then $value.value else $value end;
    ($system[0] // {}) as $system |
    ($configuration[0] // {}) as $configuration |
    ($users[0] // []) as $users |
    ($user_details[0] // [] | INDEX(.user_id | tostring)) as $user_details |
    {
      auth_mode: $system.auth_mode,
      primary_auth_mode: $system.primary_auth_mode,
      self_registration: $system.self_registration,
      users: [$users[] as $user | {
        user_id: $user.user_id,
        username: $user.username,
        sysadmin: ($user.sysadmin_flag // false),
        oidc: ($user_details[($user.user_id | tostring)].oidc // false)
      }],
      local_non_admin_users: [
        $users[] |
        select(
          (.sysadmin_flag // false) == false and
          ($user_details[(.user_id | tostring)].oidc // false) == false
        ) |
        .username
      ] | sort,
      projects: [($projects[0] // [])[] | {
        project_id,
        name,
        public: (((.metadata.public // .public // false) | tostring | ascii_downcase) == "true")
      }],
      robots: [($robots[0] // [])[] | {
        id,
        name,
        disabled: (.disabled // false),
        expires_at,
        permissions: (.permissions // [])
      }],
      oidc: {
        oidc_name: value($configuration; "oidc_name"),
        oidc_endpoint: value($configuration; "oidc_endpoint"),
        oidc_client_id: value($configuration; "oidc_client_id"),
        oidc_verify_cert: value($configuration; "oidc_verify_cert"),
        oidc_scope: value($configuration; "oidc_scope"),
        oidc_admin_group: value($configuration; "oidc_admin_group"),
        oidc_groups_claim: value($configuration; "oidc_groups_claim"),
        oidc_user_claim: value($configuration; "oidc_user_claim"),
        oidc_auto_onboard: value($configuration; "oidc_auto_onboard")
      }
    }
  ' >"$tmp/evidence.json"

"$cat_bin" "$tmp/evidence.json"
[[ $("$jq_bin" '.local_non_admin_users | length' "$tmp/evidence.json") == 0 ]] || exit 2
