profile := `hostname`

# Host IPs (LAN, SSH port 2222). laptop is Tailscale-only (roaming).
ip_discovery := "192.168.10.210"
ip_orion := "192.168.10.220"
ip_pathfinder := "192.168.10.125"
ip_kepler := "192.168.10.230"
ip_archinaut := "192.168.10.225"  # wifi (wlan0), DHCP-reserved on the wlan0 MAC; wired retired. Roaming/admin → deploy via tailscale

# Build offload to orion (Ryzen 9 5950X) via ssh-ng
orion_builder := "ssh-ng://erik@" + ip_orion + " x86_64-linux /root/.ssh/nix-builder 16 2 big-parallel,benchmark,kvm,nixos-test"

default:
    @just --list

# Resolve a host name to its LAN IP (used by sync/kick recipes)
_host-ip target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
        discovery)  echo "{{ip_discovery}}" ;;
        orion)      echo "{{ip_orion}}" ;;
        pathfinder) echo "{{ip_pathfinder}}" ;;
        kepler)     echo "{{ip_kepler}}" ;;
        archinaut)  echo "{{ip_archinaut}}" ;;
        *) echo "Unknown target: {{target}}" >&2; exit 1 ;;
    esac

# ── Local System ──────────────────────────────────────────

build target=profile:
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true

boot target=profile:
    sudo nixos-rebuild boot --flake .#{{target}} --show-trace

update:
    nix flake update

# Bump all inputs, then dry-build every host; revert the lock if any fails.
# Guards against bleeding-edge nixpkgs/git-tip inputs breaking a build.
update-safe:
    nix flake update
    just dry-all || { echo ":: dry-build failed — reverting flake.lock"; git checkout flake.lock; exit 1; }

# Bump a single input in isolation (e.g. just update-input hyprland), so a
# volatile git-tip input's breakage doesn't get tangled with a nixpkgs bump.
update-input input:
    nix flake update {{ input }}

upgrade target=profile:
    nix flake update
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true

# ── Verification ──────────────────────────────────────────

dry target=profile:
    sudo nixos-rebuild dry-build --flake .#{{target}} --show-trace

dry-all:
    sudo nixos-rebuild dry-build --flake .#pathfinder --show-trace
    sudo nixos-rebuild dry-build --flake .#discovery --show-trace
    sudo nixos-rebuild dry-build --flake .#laptop --show-trace
    sudo nixos-rebuild dry-build --flake .#orion --show-trace
    sudo nixos-rebuild dry-build --flake .#kepler --show-trace

lint:
    statix check . -c .statix.toml -i '.direnv/*'

fmt:
    nix fmt ./

fmt-check:
    alejandra --check .

# Verify every in-repo markdown link under docs/ (plus the root README/INSTALL)
# resolves to a real file. Fails on any broken link — keeps the docs index honest.
docs-check:
    #!/usr/bin/env bash
    set -euo pipefail
    broken=0
    files=$(find docs -type f -name '*.md'; ls README.md 2>/dev/null || true)
    for f in $files; do
        dir=$(dirname "$f")
        while IFS= read -r link; do
            case "$link" in http://*|https://*|mailto:*|\#*|"") continue;; esac
            target="${link%%#*}"
            [ -z "$target" ] && continue
            if [ ! -e "$dir/$target" ]; then
                echo "BROKEN: $f -> $link"
                broken=$((broken+1))
            fi
        done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
    done
    if [ "$broken" -gt 0 ]; then
        echo ":: docs-check FAILED — $broken broken link(s)"
        exit 1
    fi
    echo ":: docs-check OK — all in-repo doc links resolve"

check:
    @echo ":: Checking docs..."
    just docs-check
    @echo ":: Linting..."
    just lint
    @echo ":: Checking format..."
    just fmt-check
    @echo ":: Dry building all hosts..."
    just dry-all
    @echo ":: All checks passed"

eval:
    nix flake check

# ── Remote Deploy ─────────────────────────────────────────
# laptop is Tailscale only (roaming), use: just deploy laptop <tailscale-ip> 2222

switch-discovery:
    just deploy discovery {{ip_discovery}} 2222

switch-orion:
    just deploy orion {{ip_orion}} 2222

switch-pathfinder:
    just deploy pathfinder {{ip_pathfinder}} 2222

switch-kepler:
    just deploy kepler {{ip_kepler}} 2222

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
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-substitutes --sudo --show-trace

deploy-boot target ip port="2222" user="erik":
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild boot --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-substitutes --sudo --show-trace

verify target ip port="2222" user="erik":
    @echo ":: Verifying {{target}}..."
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Failed units:' && systemctl --failed --no-legend"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Tailscale:' && tailscale status --peers=false"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Syncthing:' && systemctl is-active syncthing"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Home-manager:' && systemctl status home-manager-{{user}} --no-pager -n0"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: SOPS age key:' && test -f ~/.config/sops/age/keys.txt && echo 'present' || echo 'MISSING'"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: SOPS staging cleanup:' && test ! -f /var/lib/sops-staging/age-keys.txt && echo 'cleaned' || echo 'STILL EXISTS'"
    @echo ":: Verification complete for {{target}}"

# ── kepler k3s cluster ────────────────────────────────────

# Fetch cp-1's admin kubeconfig → repoint at the LB admin endpoint (via discovery)
# → rename context to 'pastelariadev' → ~/.kube/config. Run after a fresh laptop
# or a cluster reform. cp-1 (clusterInit server, 10.250.0.11) is on the private
# subnet, reached by agent-forward (kepler sshd disallows TCP forwarding).
kubeconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    ssh -A -p 2222 erik@{{ip_kepler}} \
        'ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 "cat /etc/rancher/k3s/k3s.yaml"' \
        | sed 's#https://127.0.0.1:6443#https://k8s.pastelariadev.com:6443#' \
        | sed 's/: default$/: pastelariadev/' \
        > ~/.kube/config
    chmod 600 ~/.kube/config
    echo ":: kubeconfig → context $(kubectl config current-context)"
    kubectl get nodes

# LAN-direct kubeconfig → apiserver VIP 192.168.10.245 (cert SAN covers it),
# bypassing discovery's stream-proxy. Use on the kepler LAN or when discovery is
# down (grill §5 — admin access must not depend on a second host). Separate file;
# use via `KUBECONFIG=~/.kube/pastelariadev-lan.yaml kubectl …`.
kubeconfig-lan:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    ssh -A -p 2222 erik@{{ip_kepler}} \
        'ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 "cat /etc/rancher/k3s/k3s.yaml"' \
        | sed 's#https://127.0.0.1:6443#https://192.168.10.245:6443#' \
        | sed 's/: default$/: pastelariadev-lan/' \
        > ~/.kube/pastelariadev-lan.yaml
    chmod 600 ~/.kube/pastelariadev-lan.yaml
    echo ":: LAN kubeconfig → ~/.kube/pastelariadev-lan.yaml (context pastelariadev-lan)"
    KUBECONFIG=~/.kube/pastelariadev-lan.yaml kubectl get nodes

# ── archinaut (BIQU B1 print host, RPi3 aarch64) ──────────
# archinaut is aarch64: build on orion (binfmt qemu), substitute to the Pi.
# Bootstrap: build the SD image, dd it, first boot wired (see
# docs/proposals/2026-06-16-printer-nixos-host.md §9), then seed config.

# Build a bootable SD image (aarch64) on orion. target=archinaut (production) or
# archinaut-base (rescue / kernel-direct prototype — flash a SPARE card, boot
# with the printer ON to prove no-u-boot boot, RFC 2026-06-20).
build-archinaut-sd target="archinaut":
    nix build .#nixosConfigurations.{{target}}.config.system.build.sdImage \
        --builders 'ssh-ng://erik@{{ip_orion}}?ssh-key=/root/.ssh/nix-builder aarch64-linux' \
        --max-jobs 0 --show-trace --out-link result-{{target}}-sd
    @echo ":: image at result-{{target}}-sd/sd-image/ — flash with:"
    @echo "   zstd -dc result-{{target}}-sd/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M oflag=direct status=progress conv=fsync"

# Deploy archinaut: evaluate locally, build aarch64 on orion, push to the Pi.
switch-archinaut:
    NIX_SSHOPTS="-p 2222" nixos-rebuild switch --flake .#archinaut \
        --target-host erik@{{ip_archinaut}} \
        --build-host erik@{{ip_orion}} \
        --use-substitutes --sudo --show-trace

# Seed /var/lib/klipper from the klipper-biqu repo (printer.cfg, mainsail.cfg,
# macros). mutableConfig keeps these; SAVE_CONFIG/Mainsail edits persist.
seed-archinaut:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="$(readlink -f references/repos/klipper-biqu)/printer_data/config/"
    rsync -av --rsync-path="sudo rsync" -e "ssh -p 2222" \
        "$SRC" erik@{{ip_archinaut}}:/var/lib/klipper/
    ssh -p 2222 erik@{{ip_archinaut}} \
        "sudo chown -R klipper:klipper /var/lib/klipper && sudo systemctl restart klipper moonraker"
    echo ":: seeded — check Mainsail at http://{{ip_archinaut}}"

# ── Servarr sync (compose stacks) ─────────────────────────
# Push local servarr/ working tree to a host's /home/erik/servarr/ so that
# unpushed changes can be deployed without going through GitHub. The local
# symlink at `references/repos/servarr` points at ~/Documents/erik/servarr
# (alongside `references/repos/hermes-flake` and
# `references/repos/home-assistant-config`).
# Use these when you want to test compose changes before pushing main.

sync-servarr target:
    just _sync-servarr {{target}}

_sync-servarr-default:
    just _sync-servarr {{profile}}

_sync-servarr target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    SRC="$(readlink -f references/repos/servarr)"
    # Single-source the hermes persona: desktop-nixos owns the canonical
    # SOUL.md; mirror it into the servarr tree so the deployed file can't
    # drift. hermes only READS SOUL.md at runtime (seed-if-missing), so a
    # managed read-only mirror is safe. The servarr copy is thus generated —
    # edit modules/hosts/discovery/homelab-SOUL.md, never the mirror.
    if [ "{{target}}" = "discovery" ]; then
        cp modules/hosts/discovery/homelab-SOUL.md \
           "$SRC/machines/discovery/config/hermes-agent/SOUL.md"
    fi
    echo ":: Syncing $SRC/machines/{{target}} → erik@$IP:/home/erik/servarr/machines/{{target}}/"
    ssh -p 2222 erik@$IP 'mkdir -p /home/erik/servarr/machines/{{target}}'
    rsync -azv \
        --no-perms --no-owner --no-group --no-times \
        --exclude '.env' --exclude '.env.sops' \
        --exclude '__pycache__' --exclude '.DS_Store' \
        --exclude 'config/adguard/AdGuardHome.yaml' \
        --exclude 'config/ntfy/cache' \
        --exclude '.harbor-installer' \
        -e "ssh -p 2222" \
        "$SRC/machines/{{target}}/" \
        "erik@$IP:/home/erik/servarr/machines/{{target}}/"

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
        --no-perms --no-owner --no-group --no-times \
        --exclude '.git' --exclude '__pycache__' --exclude '.DS_Store' \
        -e "ssh -p 2222" \
        "$SRC/" \
        "erik@$IP:/home/erik/hermes-skills/"

# Sync a single host stack file + its config dir (faster, doesn't touch others):
#   just sync-stack kepler ai-serving
sync-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    SRC="$(readlink -f references/repos/servarr)"
    echo ":: Syncing {{stack}} files → erik@$IP:/home/erik/servarr/machines/{{target}}/"
    ssh -p 2222 erik@$IP 'mkdir -p /home/erik/servarr/machines/{{target}}/config/{{stack}}'
    rsync -azv --no-perms --no-owner --no-group --no-times -e "ssh -p 2222" \
        "$SRC/machines/{{target}}/{{stack}}.yml" \
        "erik@$IP:/home/erik/servarr/machines/{{target}}/{{stack}}.yml" || true
    if [ -d "$SRC/machines/{{target}}/config/{{stack}}" ]; then
        rsync -azv --no-perms --no-owner --no-group --no-times -e "ssh -p 2222" \
            "$SRC/machines/{{target}}/config/{{stack}}/" \
            "erik@$IP:/home/erik/servarr/machines/{{target}}/config/{{stack}}/"
    fi

# After syncing, kick the compose stack on the remote host:
#   just kick-stack kepler ai-serving
kick-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@$IP "systemctl --user start podman-compose-{{stack}}.service"
    ssh -p 2222 erik@$IP "systemctl --user status podman-compose-{{stack}}.service --no-pager -n10"

# Remote ai-serving health probe (runs from your workstation, hits kepler:<ports>)
ai-kepler-health:
    @just verify-port kepler {{ip_kepler}} 7997
    @just verify-port kepler {{ip_kepler}} 8001
    @just verify-port kepler {{ip_kepler}} 9000
    @just verify-port kepler {{ip_kepler}} 10200

verify-port target ip port:
    @nc -z -w 2 {{ip}} {{port}} && echo ":: {{target}}:{{port}} ✅" || echo ":: {{target}}:{{port}} ❌"

# ── Provisioning (first install) ──────────────────────────

nixos-anywhere target ip luks-pass="" user="nixos":
    #!/usr/bin/env bash
    set -euo pipefail
    LUKS_PASS="{{luks-pass}}"
    if [ -z "$LUKS_PASS" ]; then
        read -rsp "Enter LUKS password: " LUKS_PASS
        echo
    fi
    mkdir -p /tmp/nixos-extra/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    LUKS_FILE=$(mktemp)
    printf '%s' "$LUKS_PASS" > "$LUKS_FILE"
    trap 'rm -f "$LUKS_FILE"; rm -rf /tmp/nixos-extra' EXIT
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{target}} \
        --extra-files /tmp/nixos-extra \
        --disk-encryption-keys /tmp/luks-password.txt "$LUKS_FILE" \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/{{target}}/_hw-generated.nix \
        {{user}}@{{ip}}

deploy-orion:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra' EXIT
    # NOTE: No LUKS flag — Orion has no disk encryption (R010)
    # Target: nixos@192.168.10.220 (NixOS ISO, port 22)
    # Before running: boot Orion from NixOS ISO, confirm device paths with:
    #   ssh nixos@192.168.10.220 'lsblk -d -o NAME,SIZE,TYPE,MODEL | sort'
    # then update modules/hosts/orion/hardware.nix if nvme0n1/sda/sdb differ.
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#orion \
        --extra-files /tmp/nixos-extra \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/orion/_hw-generated.nix \
        nixos@192.168.10.220

deploy-discovery:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra' EXIT
    # NOTE: No LUKS on Discovery
    # Target: nixos@192.168.10.210 (NixOS ISO, port 22)
    # WARNING: sda and sdc will be wiped. sdb (/home/erik/vault) is NOT touched by disko.
    # Before running: boot Discovery from NixOS ISO, confirm device paths with:
    #   ssh nixos@192.168.10.210 'lsblk -d -o NAME,SIZE,TYPE,MODEL | sort'
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#discovery \
        --extra-files /tmp/nixos-extra \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/discovery/_hw-generated.nix \
        nixos@192.168.10.210

deploy-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra-kepler/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra-kepler/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra-kepler/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra-kepler' EXIT
    # Target: nixos@192.168.10.112 (NixOS ISO, port 22)
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#kepler \
        --extra-files /tmp/nixos-extra-kepler \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/kepler/_hw-generated.nix \
        nixos@192.168.10.112

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

# ── Secrets ───────────────────────────────────────────────

age-private:
    mkdir -p ~/.config/sops/age
    nix run nixpkgs#ssh-to-age -- \
        -private-key -i ~/.ssh/id_ed25519 \
        > ~/.config/sops/age/keys.txt

age-public:
    nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt

sops:
    nix run nixpkgs#sops -- secrets/sops/secrets.yaml

add-ampagent:
    #!/usr/bin/env bash
    set -euo pipefail
    deb=$(find . -maxdepth 1 -name 'ampagent-*kace.nstech.com.br*.deb' ! -name '* copy*' -print -quit)
    if [ -z "$deb" ]; then
        echo "ERROR: No ampagent .deb found in project root"
        echo "  Drop the original .deb (with token in filename) here and retry"
        exit 1
    fi
    echo ":: Found: $deb"

    # Extract enrollment token from filename (part after '+' before '.deb')
    token=$(basename "$deb" | sed -n 's/.*\.com\.br+\(.*\)\.deb/\1/p')
    if [ -z "$token" ]; then
        echo "ERROR: Could not extract token from filename"
        exit 1
    fi
    echo ":: Extracted enrollment token"

    # Add clean-named .deb to nix store
    cp "$deb" ampagent-15.0.54.deb
    nix-store --add-fixed sha256 ampagent-15.0.54.deb
    rm ampagent-15.0.54.deb
    echo ":: Added .deb to nix store"

    # Upsert kace_token in sops secrets
    nix run nixpkgs#sops -- set secrets/sops/secrets.yaml '["kace_token"]' "\"$token\""
    echo ":: Updated kace_token in sops"

    echo ":: Done. You can delete the original: rm \"$deb\""

rsync-sops ip port="22" user="erik":
    rsync -azv \
        --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" \
        -e "ssh -l {{user}} -o Port={{port}}" \
        ~/.config/sops/age/ {{user}}@{{ip}}:~/.config/sops/age/

# ── Maintenance ───────────────────────────────────────────

gc days="5":
    nix-collect-garbage --delete-older-than {{days}}d

store-repair:
    sudo nix-store --verify --check-contents --repair

cache-keygen:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ":: Generating nix-serve cache signing key pair"
    sudo nix-store --generate-binary-cache-key discovery /etc/nix/cache-priv-key.pem /tmp/cache-pub-key.pem
    sudo chmod 600 /etc/nix/cache-priv-key.pem
    echo ":: Private key: /etc/nix/cache-priv-key.pem"
    echo ":: Public key:"
    cat /tmp/cache-pub-key.pem
    echo
    echo ":: Add this public key to nix.settings.trusted-public-keys in Story 3.3"
