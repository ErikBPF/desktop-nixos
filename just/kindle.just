test-kindle-release-agent:
    python -m unittest tests/kindle-release-agent/test_agent.py

# Verify a signed kindle-dash release and mirror its exact digest into the
# project-scoped Harbor library using the root-only Vault Agent render.
mirror-kindle version digest:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{version}}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
      echo "invalid version: {{version}}" >&2
      exit 1
    }
    [[ "{{digest}}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      echo "invalid digest: {{digest}}" >&2
      exit 1
    }
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" sudo bash -s -- "{{version}}" "{{digest}}" <<'REMOTE'
      set -euo pipefail
      env_file=/run/vault-agent/harbor.env
      export HARBOR_ROBOT_USER="$(sed -n 's/^HARBOR_ROBOT_USER=//p' "$env_file")"
      export HARBOR_ROBOT_SECRET="$(sed -n 's/^HARBOR_ROBOT_SECRET=//p' "$env_file")"
      [[ -n "$HARBOR_ROBOT_USER" && -n "$HARBOR_ROBOT_SECRET" ]]
      exec /run/current-system/sw/bin/harbor-mirror "$1" "$2"
    REMOTE

# Verify the fixed Kindle deployment gates without accepting arbitrary
# container, volume, endpoint, or owner inputs.
verify-kindle digest:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{digest}}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      echo "invalid digest: {{digest}}" >&2
      exit 1
    }
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" bash -s -- "{{digest}}" <<'REMOTE'
      set -euo pipefail
      expected="$1"
      for _ in $(seq 1 30); do
        status="$(docker inspect kindle-dash | jq -r '.[0].State.Health.Status // empty')"
        [[ "$status" == healthy ]] && break
        sleep 2
      done
      [[ "$status" == healthy ]]
      inspect="$(docker inspect kindle-dash)"
      [[ "$(jq -r '.[0].Config.Labels["com.docker.compose.project"]' <<<"$inspect")" == kindle-dash ]]
      jq -er '.[0].Mounts[] | select(.Name == "discovery_kindle_dash_data" and .Destination == "/data")' \
        <<<"$inspect" >/dev/null
      image_id="$(jq -r '.[0].Image' <<<"$inspect")"
      docker image inspect "$image_id" |
        jq -er --arg digest "$expected" '.[0].RepoDigests[] | select(endswith("@" + $digest))' >/dev/null
      png_magic="$(
        curl --fail --silent --show-error \
          --resolve kindle.homelab.pastelariadev.com:80:192.168.10.210 \
          http://kindle.homelab.pastelariadev.com/dash.png |
          head -c 8 | od -An -tx1 | tr -d ' \n'
      )"
      [[ "$png_magic" == 89504e470d0a1a0a ]]
      printf 'kindle verified: digest=%s health=%s owner=kindle-dash volume=discovery_kindle_dash_data png=ok\n' \
        "$expected" "$status"
    REMOTE

# Seed the Kindle dashboard runtime credentials into OpenBao from the sops
# bootstrap record (`kindle_dash:` in secrets/sops/secrets.yaml). The live
# values win after first boot because they rotate: the Claude and Codex refresh
# tokens rotate on use, and the opencode console cookie rotates in a browser.
# This writes only the keys the KV entry is missing, so re-running it never
# overwrites a rotated value. Rotate one key deliberately by patching
# secret/home/kindle-dash, then recreating the stack. Secret values travel only
# over stdin and never print.
seed-kindle-dash-vault:
    #!/usr/bin/env bash
    set -euo pipefail
    payload_file="$(mktemp)"
    trap 'rm -f "$payload_file"' EXIT
    chmod 600 "$payload_file"
    sops --decrypt --output-type json --extract '["kindle_dash"]' \
      secrets/sops/secrets.yaml |
      jq -e 'select(
          keys == [
            "KINDLE_DASH_CLAUDE_REFRESH_TOKEN",
            "KINDLE_DASH_CODEX_REFRESH_TOKEN",
            "KINDLE_DASH_HA_TOKEN",
            "KINDLE_DASH_OPENCODE_AUTH_COOKIE"
          ]
          and all(.[]; type == "string" and length > 0)
        )' > "$payload_file"
    token="$(
      sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml
    )"
    {
      printf '%s' "$token" | base64 -w0
      printf '\n'
      base64 -w0 "$payload_file"
      printf '\n'
    } | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      umask 077
      IFS= read -r token_b64
      IFS= read -r payload_b64
      header="$(mktemp)"
      full="$(mktemp)"
      current="$(mktemp)"
      add="$(mktemp)"
      patch="$(mktemp)"
      trap "rm -f \"$header\" \"$full\" \"$current\" \"$add\" \"$patch\"" EXIT
      chmod 600 "$header" "$full" "$current" "$add" "$patch"
      printf "X-Vault-Token: %s\n" "$(printf "%s" "$token_b64" | base64 --decode)" > "$header"
      unset token_b64
      printf "%s" "$payload_b64" | base64 --decode > "$full"
      unset payload_b64
      http_code="$(curl --header @"$header" --silent --show-error \
        --output "$current" --write-out "%{http_code}" \
        http://127.0.0.1:8200/v1/secret/data/home/kindle-dash)"
      case "$http_code" in
        200) exists=1 ;;
        404)
          exists=0
          printf "{\"data\":{\"data\":{}}}" > "$current"
          ;;
        *)
          echo "kindle_dash_vault=error read_status=$http_code" >&2
          exit 1
          ;;
      esac
      jq --slurpfile have "$current" \
        "with_entries(select(.key as \$k | (\$have[0].data.data | has(\$k)) | not))" \
        "$full" > "$add"
      missing="$(jq -r "keys | join(\",\")" "$add")"
      if [ -z "$missing" ]; then
        echo "kindle_dash_vault=ready seeded_keys=none existing=4"
      elif [ "$exists" -eq 1 ]; then
        jq -c "{data: .}" "$add" > "$patch"
        curl --header @"$header" --silent --show-error --fail --request PATCH \
          --header "Content-Type: application/merge-patch+json" \
          --data-binary @"$patch" \
          http://127.0.0.1:8200/v1/secret/data/home/kindle-dash >/dev/null
        echo "kindle_dash_vault=seeded keys=$missing"
      else
        jq -c "{data: ., options: {cas: 0}}" "$full" > "$patch"
        curl --header @"$header" --silent --show-error --fail --request POST \
          --data-binary @"$patch" \
          http://127.0.0.1:8200/v1/secret/data/home/kindle-dash >/dev/null
        echo "kindle_dash_vault=created keys=$missing"
      fi
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/kindle-dash \
        | jq -e "
          .data.data | keys == [
            \"KINDLE_DASH_CLAUDE_REFRESH_TOKEN\",
            \"KINDLE_DASH_CODEX_REFRESH_TOKEN\",
            \"KINDLE_DASH_HA_TOKEN\",
            \"KINDLE_DASH_OPENCODE_AUTH_COOKIE\"
          ]
        " >/dev/null
    '

# Prove the Kindle dashboard render is fresh and least-privilege without
# printing or hashing any secret value.
verify-kindle-dash-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/kindle-dash.env)" = "440 root docker"
      sudo -u erik head -c0 /run/vault-agent/kindle-dash.env
      if sudo -u nobody head -c0 /run/vault-agent/kindle-dash.env 2>/dev/null; then
        echo "nobody unexpectedly read Kindle dashboard render" >&2
        exit 1
      fi
      sudo find /run/vault-agent/kindle-dash.env -mmin -15 -print -quit | grep -q .
      actual="$(sudo grep -v '^#' /run/vault-agent/kindle-dash.env | cut -d= -f1 | sort -u)"
      expected="$(printf "KINDLE_DASH_CLAUDE_REFRESH_TOKEN\nKINDLE_DASH_CODEX_REFRESH_TOKEN\nKINDLE_DASH_HA_TOKEN\nKINDLE_DASH_OPENCODE_AUTH_COOKIE")"
      test "$actual" = "$expected"
      echo "kindle_dash_render=ready mode=0440 owner=root group=docker fresh=true keys=4"
    '

# Kindle release-agent operator entry points. Remote access stays fixed to
# Discovery and emits no credential material.
verify-kindle-release-agent:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
      set -euo pipefail
      echo "timer_enabled=$(systemctl is-enabled kindle-release-agent.timer 2>/dev/null || true)"
      systemctl show kindle-release-agent.timer \
        -p ActiveState -p LastTriggerUSec -p NextElapseUSecRealtime
      systemctl show kindle-release-agent.service \
        -p ActiveState -p Result -p ExecMainStatus -p FragmentPath
      sudo -n test -s /var/lib/kindle-release-agent/state.json &&
        sudo -n cat /var/lib/kindle-release-agent/state.json || true
      test -s /var/lib/prometheus-node-exporter-text-files/kindle_release_agent.prom &&
        cat /var/lib/prometheus-node-exporter-text-files/kindle_release_agent.prom || true
      docker inspect kindle-dash |
        jq -r '.[0] | "health=\(.State.Health.Status) image=\(.Image) volume=\([.Mounts[] | select(.Name == "discovery_kindle_dash_data") | .Name] | first // "missing")"'
      png="$(mktemp)"
      trap 'rm -f "$png"' EXIT
      curl --fail --silent --show-error --max-time 30 \
        --output "$png" http://kindle.homelab.pastelariadev.com/dash.png
      head -c 8 "$png" | od -An -tx1
      journalctl -u kindle-release-agent.service -n 100 --no-pager
      journalctl -u kindle-release-agent-failure-drill.service -n 100 --no-pager
    REMOTE

diagnose-kindle-release-agent:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" \
      'sudo -n runuser -u erik -- git -C /home/erik/servarr fetch --dry-run origin main'

# Provision the release agent's narrow reporting material. Values travel only
# through stdin/tempfiles; output contains metadata, never credentials.
provision-kindle-release-reporting:
    #!/usr/bin/env bash
    set -euo pipefail
    iac_repo="$(readlink -f references/repos/homelab-iac)"
    env_file="$(mktemp)"
    trap 'rm -f "$env_file"' EXIT
    sops --decrypt --input-type dotenv --output-type dotenv "$iac_repo/.env.sops" > "$env_file"
    chmod 600 "$env_file"
    while IFS='=' read -r key value; do
      case "$key" in
        KINDLE_RELEASE_APP_ID) KINDLE_RELEASE_APP_ID="$value" ;;
        KINDLE_RELEASE_INSTALLATION_ID) KINDLE_RELEASE_INSTALLATION_ID="$value" ;;
        KINDLE_RELEASE_PRIVATE_KEY_B64) KINDLE_RELEASE_PRIVATE_KEY_B64="$value" ;;
      esac
    done < "$env_file"
    : "${KINDLE_RELEASE_APP_ID:?missing Kindle App ID}"
    : "${KINDLE_RELEASE_INSTALLATION_ID:?missing Kindle installation ID}"
    : "${KINDLE_RELEASE_PRIVATE_KEY_B64:?missing Kindle private key}"
    payload="$({
      jq -cn \
        --arg app_id "$KINDLE_RELEASE_APP_ID" \
        --arg installation_id "$KINDLE_RELEASE_INSTALLATION_ID" \
        --arg private_key_b64 "$KINDLE_RELEASE_PRIVATE_KEY_B64" \
        '{data:{app_id:($app_id|tonumber),installation_id:($installation_id|tonumber),private_key_b64:$private_key_b64}}'
    } | base64 -w0)"
    policy_payload="$(jq -cn --arg policy $'path "secret/data/shared/kindle-release" { capabilities = ["read"] }' '{policy:$policy}' | base64 -w0)"
    unset KINDLE_RELEASE_APP_ID KINDLE_RELEASE_INSTALLATION_ID KINDLE_RELEASE_PRIVATE_KEY_B64
    token="$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)"
    printf '%s\n%s\n%s\n' "$token" "$policy_payload" "$payload" | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token
      IFS= read -r policy_payload
      IFS= read -r payload
      header="$(mktemp)"
      body="$(mktemp)"
      trap "rm -f \"$header\" \"$body\"" EXIT
      printf "X-Vault-Token: %s\n" "$token" > "$header"
      unset token
      chmod 600 "$header"
      printf "%s" "$policy_payload" | base64 --decode > "$body"
      unset policy_payload
      curl --header @"$header" --silent --show-error --fail --request PUT \
        --data-binary @"$body" http://127.0.0.1:8200/v1/sys/policies/acl/kindle-release-read
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/auth/approle/role/vault-agent > "$body"
      role_payload="$(jq -c "
        .data.token_policies
        | if index(\"kindle-release-read\") then . else . + [\"kindle-release-read\"] end
        | {token_policies:.}
      " "$body")"
      printf "%s" "$role_payload" > "$body"
      unset role_payload
      curl --header @"$header" --silent --show-error --fail --request POST \
        --data-binary @"$body" http://127.0.0.1:8200/v1/auth/approle/role/vault-agent
      printf "%s" "$payload" | base64 --decode > "$body"
      unset payload
      curl --header @"$header" --silent --show-error --fail --request POST \
        --data-binary @"$body" http://127.0.0.1:8200/v1/secret/data/shared/kindle-release
      echo "kindle_release_reporting=provisioned policy=kindle-release-read"
    '

diagnose-kindle-claude-usage:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
      set -euo pipefail
      docker exec kindle-dash cat /data/claude_usage.json | jq -c '{
        session_pct, session_reset, week_pct, week_reset,
        extra_enabled, extra_pct, extra_used, extra_limit,
        extra_currency, fetched_at
      }'
      docker exec kindle-dash python -c '
      import app, json, requests
      response = requests.get(
          app.CLAUDE_USAGE_URL,
          headers={"Authorization": f"Bearer {app._access_token()}", "User-Agent": app.CLAUDE_USER_AGENT},
          timeout=20,
      )
      response.raise_for_status()
      data = response.json()
      print(json.dumps(data, sort_keys=True))
      '
      docker logs --since 24h kindle-dash 2>&1 \
        | grep '^\[usage\]' \
        | tail -20 || true
    REMOTE

run-kindle-release-agent:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo -n systemctl start kindle-release-agent.service
      systemctl show kindle-release-agent.service \
        -p ActiveState -p Result -p ExecMainStatus
    '

run-kindle-release-agent-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo -n systemctl start kindle-release-agent-failure-drill.service || true
      systemctl show kindle-release-agent-failure-drill.service \
        -p ActiveState -p Result -p ExecMainStatus
    '

# Fixed reporting-auth drill: make only the agent's GitHub config fail its
# strict mode check, prove degraded-only behavior, restore, and retry cleanly.
run-kindle-release-agent-reporting-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      secret=/run/vault-agent/kindle-release-github-app.json
      before=$(docker inspect kindle-dash | jq -r ".[0] | [.Image,.State.StartedAt] | @tsv")
      sudo -n chmod 0400 "$secret"
      trap "sudo -n chmod 0600 $secret" EXIT
      sudo -n systemctl start kindle-release-agent.service
      degraded=$(sudo -n jq -c "{version,digest,phase,degradation,rollback}" /var/lib/kindle-release-agent/state.json)
      after_failure=$(docker inspect kindle-dash | jq -r ".[0] | [.Image,.State.StartedAt] | @tsv")
      test "$before" = "$after_failure"
      printf "degraded=%s\nruntime_unchanged=true\n" "$degraded"
      sudo -n chmod 0600 "$secret"
      trap - EXIT
      sudo -n systemctl start kindle-release-agent.service
      sudo -n jq -c "{version,digest,phase,degradation,rollback}" /var/lib/kindle-release-agent/state.json
    '
