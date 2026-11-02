switch target=profile:
    just _host-guard {{target}} && \
    BUILDERS="$(just _builders {{target}})" && \
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 1

# Activate only the declarative user environment; leaves the running OS unchanged.
home-switch target=profile:
    #!/usr/bin/env bash
    set -euo pipefail
    just _host-guard {{target}}
    BUILDERS="$(just _builders {{target}})"
    activation=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.{{target}}.config.home-manager.users.erik.home.activationPackage \
      --builders "$BUILDERS" --builders-use-substitutes --max-jobs 1)
    HOME_MANAGER_BACKUP_EXT=backup "$activation/activate"

boot target=profile:
    just _host-guard {{target}} && \
    BUILDERS="$(just _builders {{target}})" && \
    sudo nixos-rebuild boot --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 1

# Build every flake check from a clean clone on Orion. The ref
# must already be published on origin/main; dirty local work is never copied.
# Orion evaluates/builds and may offload to Apollo.
check-remote ref="HEAD":
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch --quiet origin main
    commit="$(git rev-parse --verify "{{ref}}^{commit}")"
    git merge-base --is-ancestor "$commit" refs/remotes/origin/main || {
      echo ":: BLOCKED: $commit is not published on origin/main" >&2
      exit 2
    }
    remote_url="https://github.com/ErikBPF/desktop-nixos.git"
    builders="$(just _builders orion)"
    builders_b64="$(printf '%s' "$builders" | base64 -w0)"
    printf ':: remote flake checks coordinator=orion commit=%s\n' "$commit"
    remote_script='set -euo pipefail
    work=$(mktemp -d)
    trap '\''rm -rf "$work"'\'' EXIT
    git clone --quiet --no-checkout "$1" "$work/repo"
    git -C "$work/repo" checkout --quiet --detach "$2"
    test -z "$(git -C "$work/repo" status --porcelain)"
    cd "$work/repo"
    builders=$(printf %s "$3" | base64 -d)
    check_map=$(nix eval --raw .#checks --apply "
      systems: builtins.concatStringsSep \"\\n\" (builtins.concatLists
        (builtins.attrValues (builtins.mapAttrs
          (system: checks: map (name: system + \"\\t\" + name) (builtins.attrNames checks))
          systems)))")
    installables=()
    found_endeavour=false
    while IFS="$(printf "\\t")" read -r system name; do
      [ -n "$name" ] || continue
      if [ "$name" = "configurations:nixos:endeavour" ]; then
        found_endeavour=true
      fi
      installables+=(".#checks.$system.\"$name\"")
    done <<<"$check_map"
    "$found_endeavour"
    test "${#installables[@]}" -gt 0
    printf ":: building %d checks\n" "${#installables[@]}"
    exec nix build --no-link --show-trace "${installables[@]}" \
      --option builders "$builders" \
      --option builders-use-substitutes true --max-jobs 1'
    printf '%s\n' "$remote_script" | ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 \
      erik@"{{ip_orion}}" bash -s -- "$remote_url" "$commit" "$builders_b64"

# kepler intentionally excluded — deploy it on its own window so the AI
# serving stack isn't restarted as a side effect: just switch-kepler
switch-all:
    #!/usr/bin/env bash
    set -euo pipefail
    hosts=(discovery orion pathfinder)
    pids=()
    for host in "${hosts[@]}"; do
        just "switch-$host" & pids+=($!)
    done
    fail=0
    for i in "${!hosts[@]}"; do
        wait "${pids[$i]}" || { echo ":: switch-${hosts[$i]} FAILED" >&2; fail=1; }
    done
    [ "$fail" -eq 0 ] && echo ":: switch-all OK (${hosts[*]})"
    exit "$fail"

deploy target ip port="2222" user="erik":
    BUILDERS="$(just _builders {{target}})"; \
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-substitutes --sudo --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true \
        --max-jobs 1

# deploy-rs: subsequent switch WITH magic rollback (activate → re-check SSH →
# auto-revert if the host lost reachability). Uses the target-aware builders and
# permits one local fallback job when a builder is offline; the deployment
# target never compiles its own closure. Node config
# (hostname from fleet SSOT, erik@2222, per-host magic rollback) lives in
# modules/deploy-rs.nix.
#
# Rollout is canary-first: voyager is the free, recreatable canary. Its
# tailnet-only path uses activation-failure rollback because a post-activation
# Tailscale race would make magic rollback revert a good deployment. The legacy
# switch-<host>/deploy recipes stay as the escape hatch — deploy-rs adds an
# output + a recipe, it changes no host config, so reverting is "use switch-X".
#
# Pinned from the flake input (NOT `nix run github:…`) so the deployed tool
# matches flake.lock. archinaut (aarch64) activates fine here: activate.nixos is
# selected per host system in the module.
#   just deploy-rs voyager
deploy-rs target hostname="":
    BUILDERS="$(just _builders {{target}})"; \
    nix run --builders "$BUILDERS" --builders-use-substitutes --max-jobs 1 .#deploy-rs -- --skip-checks {{if hostname == "" { "" } else { "--hostname " + quote(hostname) }}} .#{{target}} \
        -- --option builders "$BUILDERS" \
           --option builders-use-substitutes true \
           --max-jobs 1

# Build and show activation changes without switching the remote system.
deploy-rs-preview target hostname="":
    BUILDERS="$(just _builders {{target}})"; \
    nix run --builders "$BUILDERS" --builders-use-substitutes --max-jobs 1 .#deploy-rs -- --skip-checks --dry-activate {{if hostname == "" { "" } else { "--hostname " + quote(hostname) }}} .#{{target}} \
        -- --option builders "$BUILDERS" \
           --option builders-use-substitutes true \
           --max-jobs 1

# Like deploy-rs, but --boot: set the new generation as the NEXT-BOOT target
# WITHOUT live-activating. For GPU/driver hosts (kepler, discovery) where an
# nvidia driver bump in the closure would mismatch the running kernel module on a
# live switch — the running services stay up until you reboot into the new gen
# (kernel + driver then match). No magic rollback (it's boot-not-activate), so
# reboot deliberately. Follow with: ssh -p 2222 erik@<ip> sudo systemctl reboot
deploy-rs-boot target:
    BUILDERS="$(just _builders {{target}})"; \
    nix run --builders "$BUILDERS" --builders-use-substitutes --max-jobs 1 .#deploy-rs -- --skip-checks --boot --fast-connection true .#{{target}} \
        -- --option builders "$BUILDERS" \
           --option builders-use-substitutes true \
           --max-jobs 1

deploy-boot target ip port="2222" user="erik":
    BUILDERS="$(just _builders {{target}})"; \
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild boot --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-substitutes --sudo --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 1

verify target ip port="2222" user="erik":
    @echo ":: Verifying {{target}}..."
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Failed units:' && systemctl --failed --no-legend"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Tailscale:' && tailscale status --peers=false"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Syncthing:' && systemctl is-active syncthing"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Home-manager:' && systemctl status home-manager-{{user}} --no-pager -n0"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: SOPS age key:' && test -f ~/.config/sops/age/keys.txt && echo 'present' || echo 'MISSING'"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: SOPS staging cleanup:' && test ! -f /var/lib/sops-staging/age-keys.txt && echo 'cleaned' || echo 'STILL EXISTS'"
    @echo ":: Verification complete for {{target}}"

# Reboot one fleet host, require a down/up transition, then prove the requested
# 7.x generation and basic control-plane health. Uses the tailnet when present.
reboot-wait target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(jq -r --arg h "{{target}}" '.hosts[$h].tailscaleIp // .hosts[$h].ip // empty' fleet.json)"
    [ -n "$IP" ] || { echo "unknown target: {{target}}" >&2; exit 1; }
    target_rev="$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock | cut -c1-7)"
    ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=10 \
      erik@"$IP" sudo systemd-run --collect --on-active=2s systemctl reboot
    echo ":: waiting for {{target}} to stop..."
    saw_down=0
    for _ in $(seq 1 30); do
      if ! timeout 5 ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@"$IP" true 2>/dev/null; then
        saw_down=1
        break
      fi
      sleep 1
    done
    (( saw_down == 1 )) || { echo ":: {{target}} never became unreachable" >&2; exit 1; }
    echo ":: waiting for {{target}} to return..."
    deadline=$((SECONDS + 600))
    while (( SECONDS < deadline )); do
      if timeout 5 ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@"$IP" \
        bash -s -- "$target_rev" <<'REMOTE'
    set -euo pipefail
    target_rev="$1"
    kernel="$(uname -r)"
    version="$(nixos-version)"
    printf 'kernel=%s\nversion=%s\n' "$kernel" "$version"
    [[ "$kernel" == 7.* ]]
    [[ "$version" == *".$target_rev"* ]]
    [[ "$(systemctl is-system-running --wait)" == running ]]
    test -z "$(systemctl --failed --no-legend)"
    test -z "$(systemctl --user --failed --no-legend)"
    tailscale status --peers=false
    REMOTE
      then
        echo ":: {{target}} healthy"
        exit 0
      fi
      sleep 2
    done
    echo ":: {{target}} did not return healthy within 600s" >&2
    exit 1

verify-pangolin-newt target:
    #!/usr/bin/env bash
    set -euo pipefail
    ip="$(just _host-ip {{target}})"
    zone="$(jq -r '.ingress.homelab.zone' fleet.json)"
    [[ "$zone" =~ ^[a-z0-9.-]+$ ]]
    ssh -p 2222 erik@"$ip" bash -s -- "$zone" <<'REMOTE'
      set -euo pipefail
      zone="$1"
      config=/var/lib/pangolin-newt/config.json
      health=/run/pangolin-newt/healthy
      systemctl is-active pangolin-newt.service
      sudo test -s "$config"
      sudo test -s "$health"
      test "$(sudo stat -c '%a %U %G' /var/lib/pangolin-newt)" = "700 root root"
      test "$(sudo stat -c '%a %U %G' "$config")" = "600 root root"
      sudo jq -e '
        (.id | type == "string" and length > 0) and
        (.secret | type == "string" and length > 0) and
        ((.provisioningKey? // "") == "")
      ' "$config" >/dev/null
      curl --fail --silent --show-error http://127.0.0.1:2112/metrics |
        grep '^# HELP ' >/dev/null
      fqdn="grafana.$zone"
      curl --fail --silent --show-error --max-time 10 \
        "https://$fqdn/api/health" |
        jq -e '.database == "ok"' >/dev/null
      echo "pangolin_newt=ready credentials=persisted health=connected metrics=ready backend=ready"
    REMOTE

# Trust a regenerated SSH host key after an explicitly authorized clean install.
trust-host-key target ip fingerprint port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    scanned="$(mktemp)"
    trap 'rm -f "$scanned"' EXIT
    ssh-keyscan -p "{{port}}" "{{ip}}" >"$scanned" 2>/dev/null
    fingerprints="$(ssh-keygen -lf "$scanned" -E sha256 | awk '{ print $2 }')"
    grep -Fxq "{{fingerprint}}" <<<"$fingerprints" || {
      echo "error: {{target}} host key mismatch: expected {{fingerprint}}, got:" >&2
      printf '%s\n' "$fingerprints" >&2
      exit 1
    }
    ssh-keygen -R '[{{ip}}]:{{port}}' >/dev/null 2>&1 || true
    cat "$scanned" >>~/.ssh/known_hosts
    echo ":: Trusted {{target}} host key {{fingerprint}}"

trust-root-builder-host-key target ip fingerprint port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    scanned=$(mktemp)
    trap 'rm -f "$scanned"' EXIT
    ssh-keyscan -p "{{port}}" "{{ip}}" >"$scanned" 2>/dev/null
    fingerprints=$(ssh-keygen -lf "$scanned" -E sha256 | awk '{ print $2 }')
    grep -Fxq "{{fingerprint}}" <<<"$fingerprints" || {
      echo "error: {{target}} builder host key mismatch" >&2
      printf '%s\n' "$fingerprints" >&2
      exit 1
    }
    sudo mkdir -p -m 700 /root/.ssh
    sudo ssh-keygen -R '[{{ip}}]:{{port}}' -f /root/.ssh/known_hosts >/dev/null 2>&1 || true
    sudo tee -a /root/.ssh/known_hosts <"$scanned" >/dev/null
    echo ":: Trusted root builder key for {{target}}: {{fingerprint}}"

# Read-only acceptance from this client; refuses on-LAN or ambiguous uplinks.
verify-roaming-dns:
    python3 scripts/verify-roaming-dns.py --off-lan

# Rotate the declarative fleet login password without exposing plaintext in
# argv, shell history, git, or remote state. The sops file keeps only the hash.
set-user-password:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rsp "New login password: " password; echo
    read -rsp "Confirm login password: " confirmation; echo
    test "$password" = "$confirmation" || { echo "error: passwords differ" >&2; exit 1; }
    hash=$(printf '%s' "$password" | nix shell nixpkgs#whois -c mkpasswd -m yescrypt -s)
    unset password confirmation
    printf '%s' "$hash" | jq -R | sops set --value-stdin secrets/sops/secrets.yaml '["hashed_password"]'
    unset hash
    echo ":: encrypted login password hash updated"

# Audit a host's actual exposure: listening sockets, the live nftables ruleset,
# and Docker/Podman published ports. Docker may rewrite firewall rules
# (https://wiki.nixos.org/wiki/Firewall), so on container hosts the published
# ports are the real attack surface — not just the NixOS firewall config.
# Read-only. Cross-check the output against docs/reference/service-exposure.md.
#   just verify-firewall discovery
verify-firewall target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    echo ":: [{{target}}] Listening TCP/UDP sockets (ss -tulpn):"
    ssh -p 2222 erik@"$IP" "sudo ss -tulpn | grep -v '127.0.0.1\|::1' || true"
    echo ":: [{{target}}] nftables ruleset (input chain):"
    ssh -p 2222 erik@"$IP" "sudo nft list ruleset 2>/dev/null | sed -n '/chain input/,/}/p' || echo '(nft unavailable)'"
    echo ":: [{{target}}] Docker published ports (host-reachable):"
    ssh -p 2222 erik@"$IP" "command -v docker >/dev/null && docker ps --format '{{{{.Names}}}}\t{{{{.Ports}}}}' | grep '0.0.0.0\|:::' || echo '(no docker / no published ports)'"
    echo ":: Compare against the intended exposure manifest before trusting this host."

# Exercise the deployed authoritative HA harness through its Vault-backed LiteLLM route.
# The synthetic request is read-only and cannot change HA state.
verify-ha-harness-model target="discovery":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'bash -se' <<'REMOTE'
    set -euo pipefail
    set -a
    source /run/vault-agent/ha-harness.env
    set +a
    payload='{
      "transcript": "qual o estado das luzes do escritório?",
      "room": "escritorio",
      "area_aliases": ["Escritório"],
      "manifest_sha256": "ffd6bd177ebd3609ffc455189f3b288c75bb27e5d9e907a2099b1c99819b2cd3",
      "manifest_source_sha256": "0c8a6ccce770e4d60bdb79d2a939e87e6fc14c0b9c7a1df01e7fd4185c9e8e94",
      "entities": [{
        "entity_id": "switch.interruptor_escritorio_l2",
        "state": "off",
        "display_name": "Parede do escritório",
        "voice_name": "Parede do escritório",
        "area_id": "escritorio",
        "area_name": "Escritório",
        "domain": "switch",
        "aliases": ["parede"],
        "semantic_type": "light_fixture",
        "operations": ["read_state", "turn_off", "turn_on"],
        "risk": {"default": "automatic", "operations": {}}
      }]
    }'
    response="$(
      curl --fail --silent --show-error \
        -H "Authorization: Bearer $HA_HARNESS_TOKEN" \
        -H 'Content-Type: application/json' \
        --data "$payload" \
        http://127.0.0.1:8091/v1/decide
    )"
    jq -c '{decision, response, calls, issues}' <<<"$response"
    jq -e '
      .decision == "execute"
      and .calls == [{"name":"HassGetState","arguments":{"area":"escritório","domain":"switch"}}]
      and (.response | contains("desligada"))
      and (.issues | type == "array")
    ' \
      <<<"$response" >/dev/null
    REMOTE

# Store Cognee's encrypted Cosign keypair in its exact OpenBao path.
# Secret values travel only through stdin and never enter argv or stdout.
bootstrap-cognee-signing private_key password_file:
    #!/usr/bin/env bash
    set -euo pipefail
    private_key={{quote(private_key)}}
    password_file={{quote(password_file)}}
    test "$(stat -c %a "$private_key")" = 600
    test "$(stat -c %a "$password_file")" = 600
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    jq -cn \
      --arg token "$token" \
      --rawfile key "$private_key" \
      --rawfile password "$password_file" \
      '{token:$token,key:$key,password:($password | rtrimstr("\n"))}' |
      ssh -p 2222 erik@{{ip_discovery}} '
        set -euo pipefail
        payload=$(cat)
        token=$(jq -er .token <<<"$payload")
        secret=$(jq -c "{COSIGN_PRIVATE_KEY:.key,COSIGN_PASSWORD:.password}" <<<"$payload")
        unset payload
        export BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$token"
        unset token
        printf "%s" "$secret" | bao kv put secret/home/cognee-signing @/dev/stdin >/dev/null
        unset secret BAO_TOKEN
        echo ":: Cognee signing secret stored"
      '
    unset token

verify-port target ip port:
    @nc -z -w 2 {{ip}} {{port}} && echo ":: {{target}}:{{port}} ✅" || echo ":: {{target}}:{{port}} ❌"

# Consume a mode-0600 Authentik bootstrap handoff into Sops and Kubernetes.
bootstrap-authentik handoff="authentik-bootstrap.secrets.json":
    scripts/bootstrap-authentik.sh {{quote(handoff)}}

bootstrap target:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ":: Bootstrap {{target}} from NixOS ISO"

    # LUKS password
    read -rsp "Enter LUKS password: " LUKS_PASS
    echo
    printf '%s' "$LUKS_PASS" > /tmp/luks-password.txt
    trap 'rm -f /tmp/luks-password.txt' EXIT

    # Partition with disko
    echo ":: Partitioning with disko..."
    sudo nix run github:nix-community/disko -- \
        --mode destroy,format,mount \
        --flake .#{{target}}

    # Install
    echo ":: Installing NixOS..."
    sudo nixos-install --flake .#{{target}} --no-root-password --show-trace

    # Stage age key (optional)
    echo
    read -rp "Path to age key (leave empty to skip): " AGE_KEY_PATH
    if [ -n "$AGE_KEY_PATH" ]; then
        sudo mkdir -p /mnt/var/lib/sops-staging/
        sudo cp "$AGE_KEY_PATH" /mnt/var/lib/sops-staging/age-keys.txt
        sudo chmod 600 /mnt/var/lib/sops-staging/age-keys.txt
        echo ":: Age key staged at /mnt/var/lib/sops-staging/age-keys.txt"
    else
        echo ":: WARNING: No age key staged — sops secrets will not be available on first boot"
    fi

    echo ":: Bootstrap complete. Reboot and enter LUKS password."

# Run both B2 jobs, then stream one file from each repository into cmp. This
# proves decrypt + restore without writing plaintext restore artifacts remotely.
verify-b2-backups:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'sudo -n bash -s' <<'REMOTE'
    set -euo pipefail
    systemctl start restic-backups-vault-b2.service
    systemctl start restic-backups-tofu-state-b2.service
    set -a
    source /run/secrets/rendered/restic-b2.env
    set +a
    restic_bin=$(systemctl show -p ExecStart --value restic-backups-tofu-state-b2.service \
      | grep -o '/nix/store/[^ ;]*/bin/restic' | head -1)
    tofu_file=$(find /home/erik/tofu-state-export -type f -print -quit)
    test -n "$tofu_file"
    RESTIC_PASSWORD_FILE=/run/secrets/restic_tofu_state_password \
      "$restic_bin" -r s3:https://s3.us-east-005.backblazeb2.com/homelab-vault/discovery/tofu-state \
      check --read-data
    RESTIC_PASSWORD_FILE=/run/secrets/restic_tofu_state_password \
      "$restic_bin" -r s3:https://s3.us-east-005.backblazeb2.com/homelab-vault/discovery/tofu-state \
      dump latest "$tofu_file" | cmp - "$tofu_file"
    RESTIC_PASSWORD_FILE=/run/secrets/vault_restic_password \
      "$restic_bin" -r s3:https://s3.us-east-005.backblazeb2.com/homelab-vault/discovery/openbao \
      check --read-data
    RESTIC_PASSWORD_FILE=/run/secrets/vault_restic_password \
      "$restic_bin" -r s3:https://s3.us-east-005.backblazeb2.com/homelab-vault/discovery/openbao \
      dump latest /var/lib/vault-snapshots/openbao.snap | cmp - /var/lib/vault-snapshots/openbao.snap
    echo "B2 backup + streamed restore verification: OK"
    REMOTE
