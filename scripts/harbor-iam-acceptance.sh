#!/usr/bin/env bash
# Read-only S2 acceptance evidence for the Authentik-backed Harbor IAM plan.
# Prints sanitized JSON only: no credentials, client secrets or user details.
set -euo pipefail

url=https://harbor.homelab.pastelariadev.com
issuer=https://authentik.homelab.pastelariadev.com/application/o/harbor/
env_file=/run/vault-agent/harbor.env
projects="dockerhub,ghcr,k8s,langfuse,library,lscr,quay,risingwave"
reader_group=harbor-readers
admin_group=harbor-admins
reader_robot_suffix=-harbor-reader
while (($#)); do
  case "$1" in
    --url) url=$2; shift 2 ;;
    --issuer) issuer=$2; shift 2 ;;
    --env-file) env_file=$2; shift 2 ;;
    --projects) projects=$2; shift 2 ;;
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

: >"$tmp/members.ndjson"
IFS=',' read -r -a expected_projects <<<"$projects"
for project in "${expected_projects[@]}"; do
  if ! members=$("$curl_bin" --fail --silent --show-error --max-time 15 \
    --config "$tmp/curl.conf" \
    "$url/api/v2.0/projects/$project/members?page_size=100"); then
    echo "failed to inspect members of $project" >&2
    exit 1
  fi
  printf '%s' "$members" | "$jq_bin" -c --arg project "$project" \
    '.[] | {project: $project, entity_name, entity_type, role_name}' \
    >>"$tmp/members.ndjson"
  unset members
done
"$jq_bin" -s . "$tmp/members.ndjson" >"$tmp/members.json"

# LAN path: the private flow must not depend on Cloudflare. Resolving the public
# name to a private address and completing a verified TLS handshake over it is
# the mechanical half; the Internet-down case stays an operator step.
scheme=${url%%://*}
hostport=${url#*://}
hostport=${hostport%%/*}
host=${hostport%%:*}
port=443
if [[ $scheme == http ]]; then port=80; fi
if [[ $hostport == *:* ]]; then port=${hostport##*:}; fi
lan_ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}' || true)
lan_private=false
if [[ $lan_ip =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.) ]]; then
  lan_private=true
fi
lan_status=000
if [[ $lan_private == true ]]; then
  lan_status=$("$curl_bin" --silent --output /dev/null --max-time 15 \
    --resolve "$host:$port:$lan_ip" --write-out '%{http_code}' \
    "$url/api/v2.0/systeminfo" || true)
fi

issuer_json=$("$curl_bin" --fail --silent --show-error --max-time 15 \
  "${issuer%/}/.well-known/openid-configuration")
jwks_uri=$("$jq_bin" -r '.jwks_uri // ""' <<<"$issuer_json")
jwks_status=000
if [[ -n $jwks_uri ]]; then
  jwks_status=$("$curl_bin" --silent --output /dev/null --max-time 15 \
    --write-out '%{http_code}' "$jwks_uri" || true)
fi
printf '%s' "$issuer_json" >"$tmp/issuer.json"
lan_status=${lan_status//[!0-9]/}; lan_status=${lan_status:-0}
jwks_status=${jwks_status//[!0-9]/}; jwks_status=${jwks_status:-0}

expected_projects_json=$($jq_bin -cn --arg projects "$projects" '$projects | split(",")')

# The single-quoted jq program intentionally expands inside jq, not Bash.
# shellcheck disable=SC2016
"$jq_bin" -n \
  --slurpfile system "$tmp/system.json" \
  --slurpfile configuration "$tmp/configuration.json" \
  --slurpfile users "$tmp/users.json" \
  --slurpfile user_details "$tmp/user-details.json" \
  --slurpfile members "$tmp/members.json" \
  --slurpfile robots "$tmp/robots.json" \
  --slurpfile issuer "$tmp/issuer.json" \
  --argjson expected_projects "$expected_projects_json" \
  --arg reader_group "$reader_group" \
  --arg admin_group "$admin_group" \
  --arg robot_suffix "$reader_robot_suffix" \
  --arg expected_issuer "${issuer%/}/" \
  --argjson lan_private "$lan_private" \
  --argjson lan_status "${lan_status:-0}" \
  --argjson jwks_status "${jwks_status:-0}" '
    def value($object; $key):
      ($object[$key] // null) as $value |
      if ($value | type) == "object" then $value.value else $value end;
    def gate($id; $expected; $observed; $pass):
      {id: $id, expected: $expected, observed: $observed, pass: $pass};
    ($system[0] // {}) as $system |
    ($configuration[0] // {}) as $configuration |
    ($users[0] // []) as $users |
    ($user_details[0] // [] | INDEX(.user_id | tostring)) as $user_details |
    ($members[0] // []) as $members |
    ($robots[0] // []) as $robots |
    ($issuer[0] // {}) as $issuer |
    [$users[] | select((.sysadmin_flag // false) == false) | select(($user_details[(.user_id | tostring)].oidc // false) == false) | .username] as $local_non_admin |
    [$members[] | select(.entity_type == "g" and .entity_name == $reader_group and .role_name == "guest") | .project] as $guest_projects |
    [$members[] | select(.entity_type == "g" and .entity_name == $admin_group)] as $admin_members |
    [$robots[] | select(.name | endswith($robot_suffix))] as $reader_robots |
    [$reader_robots[] | select([.permissions[].access[]? | select(.action != "pull")] | length > 0) | .name] as $pushing_readers |
    {
      generated_from: {
        harbor_auth_mode: $system.auth_mode,
        projects_checked: ($members | map(.project) | unique)
      },
      gates: [
        gate("auth_mode_oidc"; "oidc_auth"; ($system.auth_mode // ""); ($system.auth_mode == "oidc_auth")),
        gate("local_admin_retained"; "primary_auth_mode false"; ($system.primary_auth_mode // false); (($system.primary_auth_mode // false) == false)),
        gate("self_registration_closed"; "false"; ($system.self_registration // false); (($system.self_registration // false) == false)),
        gate("local_non_admin_users"; "empty migration blocker list"; $local_non_admin; ($local_non_admin | length) == 0),
        gate("oidc_admin_group"; "empty"; (value($configuration; "oidc_admin_group") // ""); ((value($configuration; "oidc_admin_group") // "") == "")),
        gate("oidc_verify_cert"; "true"; (value($configuration; "oidc_verify_cert") // false); ((value($configuration; "oidc_verify_cert") // false) == true)),
        gate("oidc_groups_claim"; "groups"; (value($configuration; "oidc_groups_claim") // ""); ((value($configuration; "oidc_groups_claim") // "") == "groups")),
        gate("oidc_user_claim"; "preferred_username"; (value($configuration; "oidc_user_claim") // ""); ((value($configuration; "oidc_user_claim") // "") == "preferred_username")),
        gate("oidc_auto_onboard"; "true"; (value($configuration; "oidc_auto_onboard") // false); ((value($configuration; "oidc_auto_onboard") // false) == true)),
        gate("oidc_scope_groups"; "scope contains groups"; (value($configuration; "oidc_scope") // ""); (((value($configuration; "oidc_scope") // "") | split(",") | map(gsub("^ +"; "")) | index("groups")) != null)),
        gate("oidc_issuer_matches_authentik"; $expected_issuer; ($issuer.issuer // ""); (($issuer.issuer // "") == $expected_issuer)),
        gate("jwks_reachable"; 200; $jwks_status; ($jwks_status == 200)),
        gate("reader_group_guest_everywhere"; ("every expected project has " + $reader_group + " guest"); ($guest_projects | sort); (($guest_projects | unique | sort) == ($expected_projects | sort))),
        gate("admin_group_unbound"; ("no " + $admin_group + " membership"); $admin_members; (($admin_members | length) == 0)),
        gate("reader_robots_pull_only"; ("no push grant on *" + $robot_suffix); $pushing_readers; (($pushing_readers | length) == 0)),
        gate("lan_path_private"; "public name resolves to a private address"; $lan_private; $lan_private),
        gate("lan_path_verified_tls"; 200; $lan_status; ($lan_status == 200))
      ]
    }
    | . + {summary: {passed: ([.gates[] | select(.pass)] | length), failed: ([.gates[] | select(.pass | not)] | length)}}
    | . + {result: (if ([.gates[] | select(.pass | not)] | length) == 0 then "pass" else "fail" end)}
  ' >"$tmp/acceptance.json"

"$cat_bin" "$tmp/acceptance.json"
[[ $("$jq_bin" -r '.result' "$tmp/acceptance.json") == "pass" ]] || exit 2
