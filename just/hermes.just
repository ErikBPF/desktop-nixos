# Validate current source in Nix sandboxes on Orion only; no host activation.
validate-hermes-orion:
    nix build --no-link -L .#checks.x86_64-linux.hermes-plugin-selftests .#checks.x86_64-linux.hermes-plugin-native .#checks.x86_64-linux.hermes-state-backup --builders '{{orion_builder}}' --builders-use-substitutes --max-jobs 0

# Local replacement for a GitHub comment command. Requeues a published head,
# runs the collector, waits for the published marker, prints the review URL.
# Request and wait for a review of one open PR head; needs local `gh` auth.
pr-review-request repo pr:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    head="$(gh pr view "{{pr}}" --repo "{{repo}}" --json headRefOid --jq .headRefOid)"
    ssh -p 2222 erik@"$IP" "sudo hermes-pr-review-request --repo '{{repo}}' --pr {{pr}} --head $head"
    ssh -p 2222 erik@"$IP" 'sudo systemctl start hermes-pr-review-collect.service'
    for _ in $(seq 1 80); do
        if marker="$(ssh -p 2222 erik@"$IP" "sudo test -s /var/lib/hermes-pr-review/published/$head.json && sudo cat /var/lib/hermes-pr-review/published/$head.json" 2>/dev/null)"; then
            printf 'published %s\n' "$(printf '%s' "$marker" | jq -r '.url // "no-url"')"
            exit 0
        fi
        sleep 15
    done
    echo "still pending after 20 minutes; inspect the ledger on discovery" >&2
    exit 1

# Read-only post-deploy proof for the Nix-owned Hermes service. Prints only a
# credential fingerprint, never the credential itself.
verify-hermes-cutoff target="discovery":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      printf "generation="; readlink /nix/var/nix/profiles/system | sed "s|.*/system-||"
      printf "unit="; systemctl is-active docker-hermes-agent.service
      printf "container="; docker inspect -f "{{"{{"}}.State.Status{{"}}"}}" hermes-agent
      printf "key_hash="; docker exec hermes-agent sh -c '\''printf %s "$OPENAI_API_KEY" | sha256sum'\'' | cut -c1-12
    '

# Push the git-versioned hermes-skills repo to a host's /home/erik/hermes-skills/
# so the hermes container can mount it read-only via skills.external_dirs.
# The compose file bind-mounts /home/erik/hermes-skills → /opt/skills-ext:ro.
# Run this before bringing the stack up (or after editing a skill) — then
# recreate the container so it re-scans. Today only discovery runs hermes.
#   just sync-hermes-skills discovery
sync-hermes-skills target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    SRC="$(readlink -f references/repos/hermes-skills)"
    echo ":: Syncing $SRC → erik@$IP:/home/erik/hermes-skills/"
    ssh -p 2222 erik@$IP 'mkdir -p /home/erik/hermes-skills'
    rsync -azv --delete \
        --no-owner --no-group --no-times \
        --chmod=D755,F644 \
        --exclude '.git' --exclude '__pycache__' --exclude '.DS_Store' \
        --exclude 'worktrees' --exclude 'graphify-out' \
        -e "ssh -p 2222" \
        "$SRC/" \
        "erik@$IP:/home/erik/hermes-skills/"

# Merge encrypted Hermes runtime envs into their Vault document.
seed-hermes-vault:
    #!/usr/bin/env bash
    set -euo pipefail
    server="$(sops --decrypt --extract '["hermes_agent"]["server_env"]' secrets/sops/secrets.yaml)"
    daedalus="$(sops --decrypt --extract '["hermes_agents"]["daedalus_env"]' secrets/sops/secrets.yaml)"
    argus="$(sops --decrypt --extract '["hermes_agents"]["argus_env"]' secrets/sops/secrets.yaml)"
    wiki="$(sops --decrypt --extract '["hermes_wiki"]["deploy_key"]' secrets/sops/secrets.yaml)"
    test -n "$server" && test -n "$daedalus" && test -n "$argus" && test -n "$wiki"
    token="$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)"
    {
      printf '%s\n' "$(printf '%s' "$token" | base64 -w0)"
      jq -cn \
        --arg server "$server" \
        --arg daedalus "$daedalus" \
        --arg argus "$argus" \
        --arg wiki "$wiki" \
        '{SERVER_ENV:$server,DAEDALUS_ENV:$daedalus,ARGUS_ENV:$argus,WIKI_DEPLOY_KEY:$wiki}' |
        base64 -w0
      printf '\n'
    } | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token_b64
      IFS= read -r value_b64
      header="$(mktemp)"
      current="$(mktemp)"
      incoming="$(mktemp)"
      payload="$(mktemp)"
      key="$(mktemp)"
      trap "rm -f \"$header\" \"$current\" \"$incoming\" \"$payload\" \"$key\"" EXIT
      chmod 600 "$header" "$current" "$incoming" "$payload" "$key"
      printf "X-Vault-Token: %s\n" "$(printf "%s" "$token_b64" | base64 --decode)" > "$header"
      unset token_b64
      printf "%s" "$value_b64" | base64 --decode > "$incoming"
      unset value_b64
      http_status="$(
        curl --header @"$header" --silent --show-error \
          --output "$current" --write-out "%{http_code}" \
          http://127.0.0.1:8200/v1/secret/data/home/hermes
      )"
      case "$http_status" in
        200) ;;
        404) printf "{\"data\":{\"data\":{}}}" > "$current" ;;
        *) echo "Hermes Vault read failed: HTTP $http_status" >&2; exit 1 ;;
      esac
      jq -s "{data:(.[0].data.data + .[1])}" "$current" "$incoming" > "$payload"
      curl --header @"$header" --silent --show-error --fail --request POST \
        --data-binary @"$payload" \
        http://127.0.0.1:8200/v1/secret/data/home/hermes >/dev/null
      expected="$(jq -r .WIKI_DEPLOY_KEY "$incoming" | sha256sum | cut -d" " -f1)"
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/hermes > "$current"
      jq -r .data.data.WIKI_DEPLOY_KEY "$current" > "$key"
      actual="$(sha256sum "$key" | cut -d" " -f1)"
      test "$actual" = "$expected"
      ssh-keygen -y -f "$key" >/dev/null
      echo "hermes_vault=seeded keys_added=4"
    '

# Verify render metadata and consumers without exposing env contents.
verify-hermes-secret-renders:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      for file in hermes-agent.env hermes-daedalus.env hermes-argus.env; do
        test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/$file)" = "400 root vault-consumers"
        sudo find "/run/vault-agent/$file" -mmin -15 -print -quit | grep -q .
        sudo test -s "/run/vault-agent/$file"
      done
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/hermes-wiki.key)" = "400 hermes hermes"
      sudo find /run/vault-agent/hermes-wiki.key -mmin -15 -print -quit | grep -q .
      sudo test -s /run/vault-agent/hermes-wiki.key
      sudo systemctl is-active docker-hermes-agent.service
      sudo systemctl is-active docker-hermes-daedalus.service
      sudo systemctl is-active docker-hermes-argus.service
      sudo systemctl is-active hermes-wiki-clone.service
      echo "hermes_render=ready mode=0400 fresh=true files=4 wiki_owner=hermes"
    '

# Read-only failure detail for the declarative Hermes wiki checkout.
diagnose-hermes-wiki:
    IP="$(just _host-ip discovery)"; ssh -p 2222 erik@"$IP" 'sudo systemctl status hermes-wiki-clone.service --no-pager -l || true; sudo journalctl -u hermes-wiki-clone.service -b --no-pager -n 100'

# Verify all Hermes role containers and Daedalus MCP registration without
# exposing API keys or decrypted secret contents.
sync-cleytin-grafana-hmac:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    token="$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)"
    printf '%s\n' "$(printf '%s' "$token" | base64 -w0)" | ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      IFS= read -r token_b64
      secret="$(sudo sed -n "s/^WEBHOOK_GRAFANA_ALERTS_SECRET=//p" /run/vault-agent/hermes-argus.env)"
      test -n "$secret"
      export BAO_ADDR=http://127.0.0.1:8200
      export BAO_TOKEN="$(printf "%s" "$token_b64" | base64 --decode)"
      unset token_b64
      jq -cn --arg secret "$secret" "{argus_webhook_hmac:\$secret}" |
        bao kv patch -mount=secret shared/discord @/dev/stdin >/dev/null
      unset BAO_TOKEN
      sudo systemctl restart vault-agent.service
      for attempt in {1..20}; do
        rendered="$(sudo sed -n "s/^WEBHOOK_GRAFANA_ALERTS_SECRET=//p" /run/vault-agent/discord.env)"
        if [ "$rendered" = "$secret" ]; then
          echo ":: Cleytin/Grafana hmac=matched"
          exit 0
        fi
        sleep 1
      done
      echo ":: Cleytin/Grafana HMAC render did not converge" >&2
      exit 1
    '

test-cleytin-grafana-route:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
    set -euo pipefail
    sudo test -s /run/vault-agent/hermes-argus.env
    status="$(docker exec hermes-argus python3 -c 'import hashlib,hmac,json,os,time,urllib.request; assert os.environ["WEBHOOK_SECRET"] == os.environ["WEBHOOK_GRAFANA_ALERTS_SECRET"]; payload={"receiver":"Cleytin canary","status":"firing","alerts":[{"status":"firing","labels":{"alertname":"CleytinGrafanaRouteCanary","instance":"discovery","severity":"warning"},"annotations":{"summary":"Synthetic route canary; no incident. Reply with a one-line TEST verdict."}}]}; body=json.dumps(payload,separators=(",",":")).encode(); signature=hmac.new(os.environ["WEBHOOK_GRAFANA_ALERTS_SECRET"].encode(),body,hashlib.sha256).hexdigest(); request=urllib.request.Request("http://127.0.0.1:8644/webhooks/grafana-alerts",data=body,headers={"Content-Type":"application/json","X-Webhook-Signature":signature,"X-Request-ID":f"cleytin-grafana-canary-{int(time.time())}"}); print(urllib.request.urlopen(request,timeout=10).status)')"
    test "$status" = 202
    echo ":: Cleytin Grafana route canary accepted HTTP $status"
    REMOTE

# Stop only Cleytin/Argus until the next activation or boot.
stop-hermes-argus:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=10 erik@"$IP" '
      set -euo pipefail
      sudo systemctl stop \
        hermes-argus-healthcheck.timer \
        hermes-argus-healthcheck.service \
        docker-hermes-argus.service
      ! sudo systemctl is-active --quiet hermes-argus-healthcheck.timer
      ! sudo systemctl is-active --quiet docker-hermes-argus.service
      if ! state="$(docker inspect --format="{{"{{"}}.State.Status{{"}}"}}" hermes-argus 2>/dev/null)"; then
        state=absent
      fi
      test "$state" != running
      sudo systemctl is-active docker-hermes-agent.service docker-hermes-daedalus.service
      printf ":: hermes-argus state=%s timer=stopped peers=running\n" "$state"
    '

# Resume only Cleytin/Argus after a maintenance window.
start-hermes-argus:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=10 erik@"$IP" '
      set -euo pipefail
      sudo systemctl start docker-hermes-argus.service hermes-argus-healthcheck.timer
      for attempt in {1..20}; do
        docker inspect hermes-argus >/dev/null 2>&1 && break
        test "$attempt" -lt 20 || exit 1
        sleep 1
      done
      sudo systemctl is-active \
        docker-hermes-argus.service \
        hermes-argus-healthcheck.timer \
        docker-hermes-agent.service \
        docker-hermes-daedalus.service
    '
    just hermes-agents-health

hermes-agents-health:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      for name in hermes-agent hermes-daedalus hermes-argus; do
        state=$(docker inspect --format="{{"{{"}}.State.Status{{"}}"}}" "$name")
        health=$(docker inspect --format="{{"{{"}}if .State.Health{{"}}"}}{{"{{"}}.State.Health.Status{{"}}"}}{{"{{"}}else{{"}}"}}none{{"{{"}}end{{"}}"}}" "$name")
        printf ":: %s state=%s health=%s\n" "$name" "$state" "$health"
        test "$state" = running
      done
      require_env() {
        if ! docker exec "$1" env | grep -qE "^$2=.+"; then
          printf ":: %s %s=missing\n" "$1" "$2" >&2
          return 1
        fi
        printf ":: %s %s=set\n" "$1" "$2"
      }
      require_env hermes-argus WEBHOOK_GRAFANA_ALERTS_SECRET
      require_env hermes-argus WEBHOOK_SECRET
      docker exec hermes-argus cat /opt/data/config.yaml | grep -q '"'"'grafana-alerts:'"'"'
      sudo systemctl start hermes-argus-healthcheck.service
      printf ":: hermes-argus gateway=running discord=connected heartbeat=fresh\n"
      for attempt in {1..20}; do
        if docker exec hermes-argus python3 -c "import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8644/health\", timeout=2).read()" >/dev/null 2>&1; then
          break
        fi
        test "$attempt" -lt 20 || exit 1
        sleep 1
      done
      printf ":: hermes-argus route=grafana-alerts health=ready\n"
      for name in hermes-daedalus hermes-argus; do
        docker exec "$name" python3 -c "import json, os, urllib.request, yaml; u=os.environ[\"OPENAI_BASE_URL\"].rstrip(\"/\")+\"/models\"; q=urllib.request.Request(u, headers={\"Authorization\":\"Bearer \"+os.environ[\"OPENAI_API_KEY\"]}); d=json.load(urllib.request.urlopen(q, timeout=10)); default=yaml.safe_load(open(\"/opt/data/config.yaml\"))[\"model\"][\"default\"]; assert default in {m[\"id\"] for m in d[\"data\"]}" >/dev/null
        printf ":: %s litellm=authenticated model_default=authorized\n" "$name"
      done
      docker exec hermes-daedalus hermes mcp list
      require_env hermes-argus DISCORD_BOT_TOKEN
    '

# Read only public state fields for the four Hermes writers/timers.
hermes-agents-state:
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=15 erik@{{ip_discovery}} 'systemctl show docker-hermes-argus.service docker-hermes-agent.service hermes-argus-healthcheck.timer hermes-agent-healthcheck.timer --property=Id --property=LoadState --property=ActiveState --property=SubState --no-pager'

# Read-only engine preflight, using the closure already copied by backup/rehearsal.
preflight-discovery-hermes-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    python=$(nix eval --raw .#nixosConfigurations.discovery.pkgs.python3.outPath)
    [[ "$python" =~ ^/nix/store/[0-9a-z]{32}-python3-[0-9][0-9A-Za-z.+_-]*$ ]]
    nix shell --inputs-from . --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0 nixpkgs#restic -c bash scripts/hermes-state-backup.sh preflight "{{ip_discovery}}" "{{ip_kepler}}" "$python/bin/python3"

# Scoped private-state backup; no live-restore entry point.
backup-discovery-hermes-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    python=$(nix build --no-link --print-out-paths .#nixosConfigurations.discovery.pkgs.python3 --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0)
    [[ "$python" =~ ^/nix/store/[0-9a-z]{32}-python3-[0-9][0-9A-Za-z.+_-]*$ ]] && test -x "$python/bin/python3"
    nix copy --to "ssh-ng://erik@{{ip_discovery}}:2222" "$python"
    nix shell --inputs-from . --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0 nixpkgs#restic -c bash scripts/hermes-state-backup.sh backup "{{ip_discovery}}" "{{ip_kepler}}" "$python/bin/python3"

# Restore only into helper-created isolation; no writer or timer actions.
[positional-arguments]
rehearse-discovery-hermes-kepler SNAPSHOT:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "$1" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED hermes-state-backup: invalid snapshot ID' >&2; exit 1; }
    python=$(nix build --no-link --print-out-paths .#nixosConfigurations.discovery.pkgs.python3 --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0)
    [[ "$python" =~ ^/nix/store/[0-9a-z]{32}-python3-[0-9][0-9A-Za-z.+_-]*$ ]] && test -x "$python/bin/python3"
    nix copy --to "ssh-ng://erik@{{ip_discovery}}:2222" "$python"
    nix shell --inputs-from . --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0 nixpkgs#restic -c bash scripts/hermes-state-backup.sh rehearse "{{ip_discovery}}" "{{ip_kepler}}" "$python/bin/python3" "$1"
