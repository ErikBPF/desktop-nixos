# Re-render static OpenBao templates after a credential rotation.
refresh-vault-agent target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'sudo systemctl restart vault-agent.service; sudo systemctl is-active vault-agent.service; for _ in $(seq 1 100); do sudo test -s /run/vault-agent/ha-harness.env && break; sleep 0.1; done; sudo test -s /run/vault-agent/ha-harness.env; sudo chgrp docker /run/vault-agent/ha-harness.env; sudo journalctl -u vault-agent.service --no-pager -n20; sudo awk -F= '"'"'$1 == "LITELLM_API_KEY" {print $2}'"'"' /run/vault-agent/ha-harness.env | sha256sum | sed "s/ .*$/  ha-harness LITELLM_API_KEY/"'

# Prove the DS8 tools render is fresh and least-privilege without printing it.
verify-tools-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/tools.env)" = "440 root docker"
      sudo -u erik head -c0 /run/vault-agent/tools.env
      if sudo -u nobody head -c0 /run/vault-agent/tools.env 2>/dev/null; then
        echo "nobody unexpectedly read tools render" >&2
        exit 1
      fi
      sudo find /run/vault-agent/tools.env -mmin -15 -print -quit | grep -q .
      test "$(sudo grep -v '^#' /run/vault-agent/tools.env | cut -d= -f1)" = SEARXNG_SECRET_KEY
      echo "tools_render=ready mode=0440 owner=root group=docker fresh=true"
    '

# Prove the critical tunneling render is fresh and least-privilege without printing it.
verify-tunneling-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/tunneling.env)" = "440 root vault-consumers"
      sudo -u erik head -c0 /run/vault-agent/tunneling.env
      if sudo -u nobody head -c0 /run/vault-agent/tunneling.env 2>/dev/null; then
        echo "nobody unexpectedly read tunneling render" >&2
        exit 1
      fi
      sudo find /run/vault-agent/tunneling.env -mmin -15 -print -quit | grep -q .
      actual="$(sudo grep -v '^#' /run/vault-agent/tunneling.env | cut -d= -f1)"
      test "$actual" = CLOUDFLARE_TUNNEL_TOKEN
      echo "tunneling_render=ready mode=0440 owner=root group=vault-consumers fresh=true"
    '

# Prove the critical networking render is fresh and least-privilege without printing it.
verify-networking-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/networking.env)" = "440 root docker"
      sudo -u erik head -c0 /run/vault-agent/networking.env
      if sudo -u nobody head -c0 /run/vault-agent/networking.env 2>/dev/null; then
        echo "nobody unexpectedly read networking render" >&2
        exit 1
      fi
      sudo find /run/vault-agent/networking.env -mmin -15 -print -quit | grep -q .
      actual="$(sudo grep -v '^#' /run/vault-agent/networking.env | cut -d= -f1 | sort -u)"
      expected="$(printf "ADGUARD_PASSWORD\nCLOUDFLARE_API_TOKEN")"
      test "$actual" = "$expected"
      echo "networking_render=ready mode=0440 owner=root group=docker fresh=true"
    '

# Merge the encrypted AdGuard credential into the existing networking secret.
seed-adguard-vault:
    #!/usr/bin/env bash
    set -euo pipefail
    servarr_repo="$(readlink -f references/repos/servarr)"
    password="$(
      sops --decrypt --input-type dotenv --output-type json \
        "$servarr_repo/machines/discovery/.env.sops" |
        jq -er '.ADGUARD_PASSWORD | select(type == "string" and length > 0)'
    )"
    token="$(
      sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml
    )"
    {
      printf '%s' "$token" | base64 -w0
      printf '\n'
      jq -cn --arg value "$password" '{ADGUARD_PASSWORD:$value}' | base64 -w0
      printf '\n'
    } | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token_b64
      IFS= read -r value_b64
      header="$(mktemp)"
      current="$(mktemp)"
      incoming="$(mktemp)"
      payload="$(mktemp)"
      trap "rm -f \"$header\" \"$current\" \"$incoming\" \"$payload\"" EXIT
      chmod 600 "$header" "$current" "$incoming" "$payload"
      printf "X-Vault-Token: %s\n" "$(printf "%s" "$token_b64" | base64 --decode)" > "$header"
      unset token_b64
      printf "%s" "$value_b64" | base64 --decode > "$incoming"
      unset value_b64
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/networking > "$current"
      jq -s "{data:(.[0].data.data + .[1])}" "$current" "$incoming" > "$payload"
      curl --header @"$header" --silent --show-error --fail --request POST \
        --data-binary @"$payload" \
        http://127.0.0.1:8200/v1/secret/data/home/networking >/dev/null
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/networking |
        jq -e ".data.data | has(\"ADGUARD_PASSWORD\") and has(\"CLOUDFLARE_API_TOKEN\")" >/dev/null
      echo "adguard_vault=seeded networking_keys_verified=true"
    '

# Seed the three encrypted infra runtime credentials into OpenBao.
seed-infra-vault:
    #!/usr/bin/env bash
    set -euo pipefail
    servarr_repo="$(readlink -f references/repos/servarr)"
    payload="$(mktemp)"
    trap 'rm -f "$payload"' EXIT
    chmod 600 "$payload"
    sops --decrypt --input-type dotenv --output-type json \
      "$servarr_repo/machines/discovery/.env.sops" |
      jq -e '{
        data: {
          MINIO_TFSTATE_ROOT_PASSWORD,
          VAULTWARDEN_ADMIN_TOKEN,
          VAULT_DEV_ROOT_TOKEN
        }
      } | select(all(.data[]; type == "string" and length > 0))' > "$payload"
    token="$(
      sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml
    )"
    {
      printf '%s' "$token" | base64 -w0
      printf '\n'
      base64 -w0 "$payload"
      printf '\n'
    } | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token_b64
      IFS= read -r payload_b64
      header="$(mktemp)"
      body="$(mktemp)"
      trap "rm -f \"$header\" \"$body\"" EXIT
      chmod 600 "$header" "$body"
      printf "X-Vault-Token: %s\n" "$(printf "%s" "$token_b64" | base64 --decode)" > "$header"
      unset token_b64
      printf "%s" "$payload_b64" | base64 --decode > "$body"
      unset payload_b64
      curl --header @"$header" --silent --show-error --fail --request POST \
        --data-binary @"$body" http://127.0.0.1:8200/v1/secret/data/home/infra >/dev/null
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/infra |
        jq -e ".data.data | keys == [\"MINIO_TFSTATE_ROOT_PASSWORD\",\"VAULTWARDEN_ADMIN_TOKEN\",\"VAULT_DEV_ROOT_TOKEN\"]" >/dev/null
      echo "infra_vault=seeded keys=3"
    '

# Merge the two remaining encrypted ai-serving runtime credentials into OpenBao.
seed-ai-serving-vault:
    #!/usr/bin/env bash
    set -euo pipefail
    servarr_repo="$(readlink -f references/repos/servarr)"
    incoming="$(mktemp)"
    trap 'rm -f "$incoming"' EXIT
    chmod 600 "$incoming"
    sops --decrypt --input-type dotenv --output-type json \
      "$servarr_repo/machines/discovery/.env.sops" |
      jq -e '{
        LITELLM_MASTER_KEY,
        OPENCODE_ZEN_KEY
      } | select(all(.[]; type == "string" and length > 0))' > "$incoming"
    token="$(
      sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml
    )"
    {
      printf '%s' "$token" | base64 -w0
      printf '\n'
      base64 -w0 "$incoming"
      printf '\n'
    } | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token_b64
      IFS= read -r incoming_b64
      header="$(mktemp)"
      current="$(mktemp)"
      incoming="$(mktemp)"
      payload="$(mktemp)"
      trap "rm -f \"$header\" \"$current\" \"$incoming\" \"$payload\"" EXIT
      chmod 600 "$header" "$current" "$incoming" "$payload"
      printf "X-Vault-Token: %s\n" "$(printf "%s" "$token_b64" | base64 --decode)" > "$header"
      unset token_b64
      printf "%s" "$incoming_b64" | base64 --decode > "$incoming"
      unset incoming_b64
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/ai-serving > "$current"
      jq -s "{data:(.[0].data.data + .[1])}" "$current" "$incoming" > "$payload"
      curl --header @"$header" --silent --show-error --fail --request POST \
        --data-binary @"$payload" \
        http://127.0.0.1:8200/v1/secret/data/home/ai-serving >/dev/null
      curl --header @"$header" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/secret/data/home/ai-serving |
        jq -e ".data.data | has(\"LITELLM_MASTER_KEY\") and has(\"OPENCODE_ZEN_KEY\")" >/dev/null
      echo "ai_serving_vault=seeded keys_added=2"
    '

# Prove the ai-serving render is fresh and contains only the declared names.
verify-ai-serving-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      metadata="$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/ai-serving.env)"
      test "$metadata" = "440 root vault-consumers" || {
        echo "unexpected metadata: $metadata" >&2
        exit 1
      }
      sudo -u erik head -c0 /run/vault-agent/ai-serving.env
      sudo find /run/vault-agent/ai-serving.env -mmin -15 -print -quit | grep -q . || {
        echo "render is older than 15 minutes" >&2
        exit 1
      }
      actual="$(sudo grep -v "^#" /run/vault-agent/ai-serving.env | cut -d= -f1 | sort -u)"
      expected="$(printf "CLICKHOUSE_PASSWORD\nLANGFUSE_INIT_USER_PASSWORD\nLANGFUSE_PUBLIC_KEY\nLANGFUSE_SALT\nLANGFUSE_SECRET_KEY\nLITELLM_MASTER_KEY\nLITELLM_SALT_KEY\nMINIO_ROOT_PASSWORD\nOPENCODE_GO_KEY\nOPENCODE_ZEN_KEY\nUI_PASSWORD")"
      test "$actual" = "$expected" || {
        echo "unexpected names:" >&2
        printf "%s\n" "$actual" >&2
        exit 1
      }
      echo "ai_serving_render=ready mode=0440 owner=root group=vault-consumers fresh=true keys=11"
    '

# Prove the critical infra render is fresh and least-privilege without printing it.
verify-infra-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      for file in shared-db infra; do
        test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/$file.env)" = "440 root docker"
        sudo -u erik head -c0 "/run/vault-agent/$file.env"
        ! sudo -u nobody head -c0 "/run/vault-agent/$file.env" 2>/dev/null
        sudo find "/run/vault-agent/$file.env" -mmin -15 -print -quit | grep -q .
      done
      shared="$(sudo grep -v '^#' /run/vault-agent/shared-db.env | cut -d= -f1 | sort -u)"
      infra="$(sudo grep -v '^#' /run/vault-agent/infra.env | cut -d= -f1 | sort -u)"
      printf "shared_keys=%s\ninfra_keys=%s\n" "$shared" "$infra"
      test "$shared" = "$(printf "POSTGRES_PASSWORD\nREDIS_PASSWORD")"
      test "$infra" = "$(printf "MINIO_TFSTATE_ROOT_PASSWORD\nVAULT_DEV_ROOT_TOKEN\nVAULTWARDEN_ADMIN_TOKEN")"
      echo "infra_render=ready files=2 mode=0440 owner=root group=docker fresh=true"
    '

# Prove the DS8 ha-harness render is fresh and least-privilege without printing it.
verify-ha-harness-secret-render:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      sudo systemctl is-active vault-agent.service
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/ha-harness.env)" = "440 root docker"
      sudo -u erik head -c0 /run/vault-agent/ha-harness.env
      if sudo -u nobody head -c0 /run/vault-agent/ha-harness.env 2>/dev/null; then
        echo "nobody unexpectedly read ha-harness render" >&2
        exit 1
      fi
      sudo find /run/vault-agent/ha-harness.env -mmin -15 -print -quit | grep -q .
      actual="$(sudo grep -v '^#' /run/vault-agent/ha-harness.env | cut -d= -f1 | sort -u)"
      expected="$(printf "HA_HARNESS_TOKEN\nLITELLM_API_KEY")"
      test "$actual" = "$expected"
      echo "ha_harness_render=ready mode=0440 owner=root group=docker fresh=true"
    '

# List OpenBao AppRole names + non-secret role IDs from Discovery without
# exposing the root token or any secret IDs.
vault-approle-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token
      cfg=$(mktemp)
      trap "rm -f $cfg" EXIT
      printf "X-Vault-Token: %s\\n" "$token" > "$cfg"
      unset token
      chmod 600 "$cfg"
      curl --header @"$cfg" --silent --show-error --fail "http://127.0.0.1:8200/v1/auth/approle/role?list=true" \
        | jq -r ".data.keys[]" \
        | while IFS= read -r role; do
        id=$(curl --header @"$cfg" --silent --show-error --fail "http://127.0.0.1:8200/v1/auth/approle/role/$role/role-id" | jq -r .data.role_id)
        printf "%s\\t%s\\n" "$role" "$id"
      done
    '

# Show the value-free ESO policy/AppRole contract before importing it into IaC.
openbao-eso-contract:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} '
      set -euo pipefail
      IFS= read -r token
      cfg=$(mktemp)
      trap "rm -f $cfg" EXIT
      printf "X-Vault-Token: %s\n" "$token" > "$cfg"
      unset token
      chmod 600 "$cfg"
      curl --header @"$cfg" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/auth/approle/role/eso \
        | jq ".data | {bind_secret_id,token_policies,token_ttl,token_max_ttl,token_type}"
      curl --header @"$cfg" --silent --show-error --fail \
        http://127.0.0.1:8200/v1/sys/policies/acl/eso \
        | jq -r .data.policy
    '

# Revoke Authentik bootstrap access after storing a dedicated IaC token.
retire-authentik-bootstrap handoff="authentik-iac.secrets.json":
    scripts/retire-authentik-bootstrap.sh {{quote(handoff)}}

# Mint a 15-minute admin token into a private local handoff for IaC bootstrap.
mint-authentik-admin-token handoff="authentik-admin-token.secrets.json":
    bash scripts/authentik-admin-token.sh create {{quote(handoff)}}

# Revoke the temporary admin token and remove its local handoff.
revoke-authentik-admin-token handoff="authentik-admin-token.secrets.json":
    bash scripts/authentik-admin-token.sh revoke {{quote(handoff)}}

# Rotate the dedicated least-privilege provider token directly into Sops.
rotate-authentik-iac-token:
    bash scripts/rotate-authentik-iac-token.sh

age-private:
    mkdir -p ~/.config/sops/age
    nix run nixpkgs#ssh-to-age -- \
        -private-key -i ~/.ssh/id_ed25519 \
        > ~/.config/sops/age/keys.txt

age-public:
    nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt

sops:
    nix run nixpkgs#sops -- secrets/sops/secrets.yaml

rsync-sops ip port="22" user="erik":
    rsync -azv \
        --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" \
        -e "ssh -l {{user}} -o Port={{port}}" \
        ~/.config/sops/age/ {{user}}@{{ip}}:~/.config/sops/age/

# Encrypt the sops age key as a passphrase-sealed age blob (age -p) so the root
# of trust can live in git + off-premise on voyager WITHOUT exposing the key —
# recovery needs only the memorized passphrase. Store that passphrase in a
# password manager + one offline copy (paper/USB).
#
# INTERACTIVE: age -p reads the passphrase from the TTY — run in a real
# terminal (`! just escrow-age-key`), never over a non-tty pipe. age is pulled
# via nix (not installed fleet-wide). Produces the blob and self-verifies the
# round-trip; it does NOT commit or push — those are deliberate manual steps
# it prints for you.
#   ! just escrow-age-key
escrow-age-key:
    #!/usr/bin/env bash
    set -euo pipefail
    key="$HOME/.config/sops/age/keys.txt"
    blob="secrets/escrow/age-key.age"
    test -f "$key" || { echo ":: no age key at $key" >&2; exit 1; }
    age="$(nix build nixpkgs#age --no-link --print-out-paths)/bin/age"
    mkdir -p "$(dirname "$blob")"
    echo ":: Encrypting the sops age key — enter a STRONG passphrase (typed twice)."
    "$age" -p -o "$blob" "$key"
    echo ":: Verifying round-trip — re-enter the SAME passphrase to decrypt…"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    "$age" -d -o "$tmp" "$blob"
    if cmp -s "$tmp" "$key"; then
      echo ":: OK — $blob decrypts back to the live key (byte-identical)."
    else
      echo ":: MISMATCH — escrow blob does NOT match the key; do not trust it." >&2
      exit 1
    fi
    ls -l "$blob"
    echo ":: NEXT (deliberate):"
    echo "     just escrow-age-key-push       # copy off-premise to voyager"
    echo "   Store the blob in your password manager too. Do NOT commit it — this"
    echo "   repo is public; the blob is gitignored. Save the passphrase: password"
    echo "   manager + one offline copy kept off-premise."

# Copy the passphrase-sealed escrow blob off-premise to voyager (tailnet, :2222).
#   just escrow-age-key-push
escrow-age-key-push:
    #!/usr/bin/env bash
    set -euo pipefail
    blob="secrets/escrow/age-key.age"
    test -f "$blob" || { echo ":: run 'just escrow-age-key' first" >&2; exit 1; }
    ssh -p 2222 erik@{{tailscale_voyager}} 'mkdir -p ~/escrow && chmod 700 ~/escrow'
    scp -P 2222 "$blob" erik@{{tailscale_voyager}}:~/escrow/age-key.age
    ssh -p 2222 erik@{{tailscale_voyager}} 'chmod 600 ~/escrow/age-key.age && ls -l ~/escrow/age-key.age'
    echo ":: escrow copied off-premise → voyager:~/escrow/age-key.age"

# DR drill (run quarterly): prove the escrow blob still decrypts with the
# passphrase and is byte-identical to the live key. INTERACTIVE.
#   ! just escrow-age-key-verify
escrow-age-key-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    key="$HOME/.config/sops/age/keys.txt"
    blob="secrets/escrow/age-key.age"
    age="$(nix build nixpkgs#age --no-link --print-out-paths)/bin/age"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    echo ":: Decrypting escrow — enter the passphrase…"
    "$age" -d -o "$tmp" "$blob"
    if cmp -s "$tmp" "$key"; then
      echo ":: OK — escrow matches the live key."
    else
      echo ":: MISMATCH — escrow and live key differ; re-run escrow-age-key." >&2
      exit 1
    fi

# Break-glass reachability (RFC 4a/4d recovery): passphrase-seal the admin SSH
# private key so a re-imaged laptop can join the tailnet and reach Voyager to pull
# the off-premise restic repos — without it, recovery is circular (voyager's
# tailnet REST/ssh are ACL-gated to existing admin devices, and the SSH key that
# would let you in lived on the lost laptop). INTERACTIVE (age -p needs a TTY).
# The sealed blob is gitignored; store it in your PASSWORD MANAGER (cold-
# reachable) — the on-voyager copy can't help you reach voyager.
#   ! just escrow-ssh-key
escrow-ssh-key key="~/.ssh/id_ed25519":
    #!/usr/bin/env bash
    set -euo pipefail
    src="${key/#\~/$HOME}"
    blob="secrets/escrow/ssh-key.age"
    test -f "$src" || { echo ":: no SSH key at $src" >&2; exit 1; }
    age="$(nix build nixpkgs#age --no-link --print-out-paths)/bin/age"
    mkdir -p "$(dirname "$blob")"
    echo ":: Sealing $src with a passphrase (typed twice)…"
    "$age" -p -o "$blob" "$src"
    echo ":: Verifying round-trip — re-enter the SAME passphrase…"
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    "$age" -d -o "$tmp" "$blob"
    cmp -s "$tmp" "$src" && echo ":: OK — $blob decrypts back to the key." || { echo ":: MISMATCH — do not trust it." >&2; exit 1; }
    ls -l "$blob"
    echo ":: NEXT: store $blob in your password manager (cold-reachable), then:"
    echo "     scp -P 2222 $blob erik@{{tailscale_voyager}}:~/escrow/ssh-key.age   # secondary copy"
    echo "   Recover: age -d ssh-key.age > id; chmod 600 id; ssh -i id erik@voyager"

# GitHub-independent off-premise copy of every encrypted secret file (RFC 4c).
# Tars all sops-encrypted files across this repo + the sister repos and scps the
# bundle to voyager (~/escrow). The files are already age-encrypted, so the
# bundle is ciphertext — safe on voyager, still needs the age key (see the
# passphrase-age escrow, `just escrow-age-key`) to open. Run periodically; it is
# a belt-and-suspenders copy for the "GitHub lost AND laptop lost" corner.
# REFUSES to ship any candidate file that is not sops-encrypted (no ENC[ marker).
#   just escrow-secrets
escrow-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    stage="$tmp/sops-config"; mkdir -p "$stage"
    # Candidate files: this repo + sister working trees (via references/repos).
    mapfile -t files < <(
      { ls secrets/sops/*.yaml 2>/dev/null || true
        f="$(readlink -f references/repos/homelab-iac)"; [ -n "$f" ] && ls "$f"/.env.sops 2>/dev/null || true
        f="$(readlink -f references/repos/servarr)"; [ -n "$f" ] && ls "$f"/machines/*/.env.sops 2>/dev/null || true
      } | sort -u)
    test "${#files[@]}" -gt 0 || { echo ":: no candidate secret files found" >&2; exit 1; }
    n=0
    for f in "${files[@]}"; do
      if ! grep -qa 'ENC\[' "$f"; then
        echo ":: REFUSING $f — not sops-encrypted (no ENC[ marker)" >&2; exit 1
      fi
      # Flatten to repo-tagged names so the bundle is self-describing.
      rel="$(printf '%s' "$f" | sed "s#$HOME/Documents/erik/##; s#$(pwd)/##; s#/#__#g")"
      cp -a "$f" "$stage/$rel"
      n=$((n+1)); echo "   + $f"
    done
    tar -C "$tmp" -czf "$tmp/sops-config.tar.gz" sops-config
    ssh -p 2222 erik@{{tailscale_voyager}} 'mkdir -p ~/escrow && chmod 700 ~/escrow'
    scp -P 2222 "$tmp/sops-config.tar.gz" erik@{{tailscale_voyager}}:~/escrow/sops-config.tar.gz
    ssh -p 2222 erik@{{tailscale_voyager}} 'chmod 600 ~/escrow/sops-config.tar.gz && ls -l ~/escrow/sops-config.tar.gz'
    echo ":: $n encrypted secret files bundled → voyager:~/escrow/sops-config.tar.gz"
