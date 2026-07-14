profile := `hostname`

# Host IPs (LAN, SSH port 2222). laptop is Tailscale-only (roaming).
# Derived from the fleet SSOT (modules/meta.nix → fleet.json); regenerate with
# `just fleet-json` after changing an IP. archinaut is wifi (wlan0, DHCP-reserved
# on the wlan0 MAC; wired retired) — roaming/admin → deploy via tailscale.
ip_discovery := `jq -r '.hosts.discovery.ip' fleet.json`
ip_orion := `jq -r '.hosts.orion.ip' fleet.json`
ip_pathfinder := `jq -r '.hosts.pathfinder.ip' fleet.json`
ip_kepler := `jq -r '.hosts.kepler.ip' fleet.json`
ip_archinaut := `jq -r '.hosts.archinaut.ip' fleet.json`
ip_voyager := `jq -r '.hosts.voyager.ip' fleet.json`
ip_telstar := `jq -r '.hosts.telstar.ip' fleet.json`
ip_vanguard := `jq -r '.hosts.vanguard.ip' fleet.json`

# Build offload to orion (Ryzen 9 5950X) via ssh-ng
orion_builder := "ssh-ng://erik@" + ip_orion + " i686-linux,x86_64-linux,aarch64-linux /root/.ssh/nix-builder 16 2 big-parallel,benchmark,kvm,nixos-test"
kepler_builder := "ssh-ng://erik@" + ip_kepler + " x86_64-linux /root/.ssh/nix-builder 2 1 big-parallel,benchmark"

# Never ask a deployment target to build itself. Other x86_64 targets can use
# Orion as primary plus Kepler's deliberately constrained spillover capacity.
_builders target:
    @if [ "{{target}}" = kepler ]; then \
        printf '%s\n' '{{orion_builder}}'; \
    elif [ "{{target}}" = orion ]; then \
        printf '%s\n' '{{kepler_builder}}'; \
    else \
        printf '%s ; %s\n' '{{orion_builder}}' '{{kepler_builder}}'; \
    fi

default:
    @just --list

# Resolve a host name to its LAN IP from the fleet SSOT (used by sync/kick recipes)
_host-ip target:
    #!/usr/bin/env bash
    set -euo pipefail
    ip="$(jq -r --arg h "{{target}}" '.hosts[$h].ip // empty' fleet.json)"
    if [ -z "$ip" ]; then echo "Unknown target or no IP: {{target}}" >&2; exit 1; fi
    echo "$ip"

# Regenerate fleet.json from the flake SSOT (modules/meta.nix). Run after editing
# fleet.hosts; commit the result. Consumers (justfile ip_*, homelab-iac) read it.
fleet-json:
    nix eval .#fleet --json | jq . > fleet.json
    @echo ":: fleet.json regenerated — review the diff and commit"

# Fail if fleet.json is stale vs the flake (drift guard for `just check` / CI).
fleet-check:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! diff -u fleet.json <(nix eval .#fleet --json | jq .) >/dev/null; then
        echo ":: fleet-check FAILED — fleet.json is stale; run: just fleet-json" >&2
        exit 1
    fi
    echo ":: fleet-check OK — fleet.json matches the flake"

# Fleet nixpkgs drift at a glance: each host's BOOTED nixpkgs short-rev vs the
# flake's target (the root `nixpkgs` input in flake.lock — the rev a `switch`
# would build). DRIFT = host is behind/ahead of the flake. Reaches hosts over the
# tailnet (tailscaleIp, works roaming); laptop is read locally; homeassistant
# (HAOS, not NixOS) is skipped. Makes P5 drift a command, not a memory file
# (docs/proposals/2026-07-12-fleet-upgrade-hardening.md).
fleet-status:
    #!/usr/bin/env bash
    set -uo pipefail
    target=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock | cut -c1-7)
    revof() { local v="${1%% *}"; echo "${v##*.}"; }
    row() { printf '%-12s %-12s %-9s %s\n' "$1" "$2" "$target" "$3"; }
    printf '%-12s %-12s %-9s %s\n' HOST BOOTED TARGET STATE
    b=$(revof "$(nixos-version)")
    row laptop "$b" "$([ "$b" = "$target" ] && echo OK || echo DRIFT)"
    for h in $(jq -r '.hosts | keys[] | select(. != "laptop" and . != "homeassistant")' fleet.json); do
        addr=$(jq -r --arg h "$h" '.hosts[$h].tailscaleIp // empty' fleet.json)
        [ -z "$addr" ] && { row "$h" "no-tsip" "SKIP"; continue; }
        out=$(timeout 10 ssh -p 2222 -o ConnectTimeout=6 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "erik@$addr" nixos-version 2>/dev/null || true)
        if [ -z "$out" ]; then
            row "$h" "unreachable" "—"
        else
            b=$(revof "$out")
            row "$h" "$b" "$([ "$b" = "$target" ] && echo OK || echo DRIFT)"
        fi
    done

# ── Local System ──────────────────────────────────────────

build target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 0

boot target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild boot --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 0

update:
    nix flake update

# Bump all inputs, then dry-build every host; revert the lock if any fails.
# Guards against bleeding-edge nixpkgs/git-tip inputs breaking a build.
update-safe:
    git diff --quiet -- flake.lock || { echo ":: flake.lock already modified; refusing destructive rollback"; exit 1; }
    nix flake update
    just dry-all || { echo ":: dry-build failed — restoring pre-update flake.lock"; git restore --source=HEAD -- flake.lock; exit 1; }

# Bump a single input in isolation (e.g. just update-input hyprland), so a
# volatile git-tip input's breakage doesn't get tangled with a nixpkgs bump.
update-input input:
    nix flake update {{ input }}

upgrade target=profile:
    nix flake update
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 0

# ── Verification ──────────────────────────────────────────

dry target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild dry-build --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 0

# Build fleet toplevels in one scheduler invocation so independent host graphs
# run concurrently and shared derivations are built once. Does not create links.
build-all:
    nix build --no-link \
        .#nixosConfigurations.pathfinder.config.system.build.toplevel \
        .#nixosConfigurations.discovery.config.system.build.toplevel \
        .#nixosConfigurations.laptop.config.system.build.toplevel \
        .#nixosConfigurations.orion.config.system.build.toplevel \
        .#nixosConfigurations.kepler.config.system.build.toplevel \
        .#nixosConfigurations.voyager.config.system.build.toplevel \
        --builders '{{orion_builder}} ; {{kepler_builder}}' \
        --builders-use-substitutes --max-jobs 0 --show-trace

dry-all:
    sudo nixos-rebuild dry-build --flake .#pathfinder --show-trace
    sudo nixos-rebuild dry-build --flake .#discovery --show-trace
    sudo nixos-rebuild dry-build --flake .#laptop --show-trace
    sudo nixos-rebuild dry-build --flake .#orion --show-trace
    sudo nixos-rebuild dry-build --flake .#kepler --show-trace
    sudo nixos-rebuild dry-build --flake .#voyager --show-trace

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

# Dendritic contract checks (docs/reference/dendritic-contract.md). Hard-fails on
# duplicate registered module names or a _-prefixed file that registers (import-tree
# skips it, so the registration silently never happens). Reports — does NOT fail —
# large files and missing generated-file headers. Report-only by design; not wired
# into `just check` until the large domains are split (repo-structure RFC phases).
structure-check:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    echo ":: registered module name uniqueness"
    dups=$(grep -rhoE 'flake\.modules\.(nixos|home)\.[A-Za-z0-9_-]+' modules/ | sort | uniq -d || true)
    if [ -n "$dups" ]; then
        echo "FAIL: duplicate registered module names:"; echo "$dups" | sed 's/^/  /'; fail=1
    fi
    echo ":: _-prefixed files must not register (import-tree skips them)"
    while IFS= read -r f; do
        if grep -qE 'flake\.modules\.' "$f"; then
            echo "FAIL: $f registers into flake.modules but is _-prefixed"; fail=1
        fi
    done < <(find modules -name '_*.nix')
    echo ":: large files (>400 lines) — candidate domains to split (advisory)"
    find modules -name '*.nix' -exec wc -l {} + \
        | awk '$2!="total" && $1>400 {printf "  WARN: %s (%d lines)\n", $2, $1}'
    echo ":: generated hw files missing a generated-file header (advisory)"
    while IFS= read -r f; do
        head -3 "$f" | grep -qiE 'generated|do not edit' || echo "  WARN: $f has no generated-file header"
    done < <(find modules -name '_hw-generated.nix')
    if [ "$fail" -ne 0 ]; then echo ":: structure-check FAILED"; exit 1; fi
    echo ":: structure-check OK (warnings above are advisory)"

check:
    @echo ":: Checking docs..."
    just docs-check
    @echo ":: Checking fleet.json freshness..."
    just fleet-check
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

# Remote switches go through deploy-rs (magic rollback + build on Orion). The
# generic `deploy` recipe below stays as the escape hatch (plain nixos-rebuild,
# local build, no rollback) if deploy-rs itself is ever the problem.
switch-discovery:
    just deploy-rs discovery

switch-orion:
    just deploy-rs orion

switch-pathfinder:
    just deploy-rs pathfinder

# kepler is a GPU host: an nvidia driver bump in the closure mismatches the
# running kernel module on a LIVE switch (breaks the AI stack — verified). Stage
# the new generation for next boot, then reboot to activate. Own window (AI
# serving restarts on reboot).
switch-kepler:
    just deploy-rs-boot kepler
    @echo ":: kepler staged for next boot. Reboot to activate (AI stack restarts):"
    @echo "   ssh -p 2222 erik@{{ip_kepler}} sudo systemctl reboot"

# voyager is the 1 GB x86 Oracle micro: it can't compile, so build on Orion and
# substitute/activate on the target. First run after `just infect-voyager` the
# base NixOS is root@22 → `just switch-voyager root 22`; the flake config then
# moves SSH to erik@2222 → steady state `just switch-voyager`. Stages the sops
# age key so sops-nix can decrypt tailscale_authkey + the compose .env.sops.
switch-voyager user="erik" port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="{{ip_voyager}}"
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'sudo mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/tmp/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" \
        'sudo mv /tmp/age-keys.txt /var/lib/sops-staging/age-keys.txt && sudo chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#voyager \
        --target-host {{user}}@"$IP" \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true \
        --max-jobs 0 \
        --use-substitutes --sudo --show-trace

# telstar (public projects host, Oracle A1 aarch64, 12 GB). Build on Orion
# (aarch64 via binfmt), activate on the target. First run after `just
# deploy-telstar` the base is erik@2222 already (nixos-anywhere set it). Stages
# the sops age key so sops-nix can decrypt secrets.
switch-telstar user="erik" port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="{{ip_telstar}}"
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'sudo mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/tmp/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" \
        'sudo mv /tmp/age-keys.txt /var/lib/sops-staging/age-keys.txt && sudo chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#telstar \
        --target-host {{user}}@"$IP" \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true \
        --max-jobs 0 \
        --use-substitutes --sudo --show-trace

# vanguard: the 2nd 1 GB x86 Oracle micro (sibling of voyager) — same class, same
# path. First run after `just infect-vanguard noreboot=1` (box still on Ubuntu):
# `just boot-vanguard` sets the flake gen as the next boot, then reboot into it —
# do NOT reboot into infect's networkless base config first (it comes up dark).
# Once up on erik@2222, steady state is `just switch-vanguard`. Stages the sops
# age key. Roles (fleet-dns, dead-mans-switch, netbird relay2, pg-replica) are
# opt-in — enable per the vanguard proposal after provisioning.
switch-vanguard user="erik" port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="{{ip_vanguard}}"
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'sudo mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/tmp/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" \
        'sudo mv /tmp/age-keys.txt /var/lib/sops-staging/age-keys.txt && sudo chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#vanguard \
        --target-host {{user}}@"$IP" \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true \
        --max-jobs 0 \
        --use-substitutes --sudo --show-trace

# First NixOS boot on the infect path: build the flake gen on orion and set it as
# the NEXT-BOOT generation on the still-Ubuntu box (root@22; closure copied via
# substitutes — the 1 GB box never compiles). Uses `boot`, not `switch`: during
# the infect noreboot window the box still runs Ubuntu, so activation must wait
# for the reboot. Deploying the flake gen (name-agnostic DHCP + serial console)
# as the FIRST NixOS boot avoids infect's networkless base config booting dark.
# Stages the sops age key so first-boot activation can decrypt. Prereqs on the
# box: nix on root's PATH + root SSH working (Ubuntu forced-command stripped).
# Reboot after it prints an installed bootloader:  ssh root@<ip> systemctl reboot
boot-vanguard user="root" port="22":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="{{ip_vanguard}}"
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/var/lib/sops-staging/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" 'chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild boot --flake .#vanguard \
        --target-host {{user}}@"$IP" \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true \
        --max-jobs 0 \
        --use-substitutes --show-trace

# Provision vanguard exactly like voyager: nixos-infect the stock Ubuntu cloud
# image in place (1 GB x86 micro can't kexec/disko). Entrypoint
# ubuntu@{{ip_vanguard}}:22; SSH drops on reboot. noreboot=1 leaves it on Ubuntu
# for inspection (mandatory: deletes Ubuntu's EFI entry below + lets `just
# boot-vanguard` stage the flake gen before the first NixOS boot).
infect-vanguard noreboot="":
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -o StrictHostKeyChecking=accept-new ubuntu@{{ip_vanguard}} '
        set -eu
        if ! sudo swapon --show | grep -q /swapfile; then
            sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
            sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
        fi
        # Remove Ubuntus EFI boot entry + its ESP dir so firmware falls back to
        # the removable-path GRUB nixos-infect installs (Oracle UEFI otherwise
        # keeps booting Ubuntus NVRAM entry against the NixOS root → getty/sshd
        # cannot start → dark host). Deleting the /boot/efi/EFI/ubuntu dir is the
        # durable half: OCI drops NVRAM on stop/start, so an entry alone would be
        # re-scanned back; with the dir gone only BOOT/BOOT<arch>.EFI (NixOS)
        # remains. Root-caused via the OCI console-history API; voyager works
        # because its older infect already did this.
        for n in $(sudo efibootmgr | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\{0,1\} ubuntu.*/\1/Ip"); do
            echo ":: removing Ubuntu EFI entry Boot$n"
            sudo efibootmgr -b "$n" -B
        done
        sudo rm -rf /boot/efi/EFI/ubuntu
        # nixos-infect only wires a serial console for PROVIDER=hostinger and
        # generates no networking, so its base gen boots dark AND invisible on the
        # Oracle serial console. Inject an extra module (imported via NIXOS_IMPORT)
        # that adds console=ttyS0 + name-agnostic DHCP so the base gen is reachable.
        # The full-install flow is: `just infect-vanguard` (NO noreboot) — infect
        # reboots into its base gen, whose scripted stage-2 runs the NIXOS_LUSTRATE
        # first-boot purge of the old Ubuntu userland (the flake gen, on
        # systemd-initrd, never lustrates so Ubuntu units survive and break net);
        # the base gen then
        # comes up root@22 → `just switch-vanguard root 22` converges the flake gen.
        # extra.nix (base64 to avoid heredoc/quoting in this recipe) =
        #   { lib, ... }: {
        #     boot.kernelParams = lib.mkForce [ "console=tty0" "console=ttyS0,115200n8" ];
        #     networking.useDHCP = lib.mkForce true;
        #     boot.initrd.systemd.enable = lib.mkForce false;
        #   }
        # boot.initrd.systemd.enable=false is THE fix: the nixos-infect Ubuntu purge
        # (NIXOS_LUSTRATE) is handled ONLY by the SCRIPTED stage-1-init (nixpkgs
        # stage-1-init.sh); the modern systemd-initrd default SKIPS it, so the old
        # Ubuntu units (snap/networkd/multipath) survive and break networking. Force
        # scripted stage-1 for the base gen first boot so lustrate runs, giving a
        # clean NixOS. The flake gen keeps systemd-initrd (Ubuntu purged by then).
        sudo mkdir -p /etc/nixos
        echo eyBsaWIsIC4uLiB9OiB7CiAgYm9vdC5rZXJuZWxQYXJhbXMgPSBsaWIubWtGb3JjZSBbICJjb25zb2xlPXR0eTAiICJjb25zb2xlPXR0eVMwLDExNTIwMG44IiBdOwogIG5ldHdvcmtpbmcudXNlREhDUCA9IGxpYi5ta0ZvcmNlIHRydWU7CiAgYm9vdC5pbml0cmQuc3lzdGVtZC5lbmFibGUgPSBsaWIubWtGb3JjZSBmYWxzZTsKfQo= | base64 -d | sudo tee /etc/nixos/extra.nix >/dev/null
        # Pinned to a pre-#264 commit (voyager-era). #264 only changes /boot backup
        # handling, irrelevant to the conversion; kept because this SHA is proven.
        curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/7563801d3ae6/nixos-infect -o /tmp/nixos-infect
        sudo env NIX_CHANNEL=nixos-unstable NIXOS_IMPORT=./extra.nix NO_REBOOT="{{noreboot}}" bash /tmp/nixos-infect
    ' || true
    echo ":: nixos-infect done. noreboot={{noreboot}}"

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

# deploy-rs: subsequent switch WITH magic rollback (activate → re-check SSH →
# auto-revert if the host lost reachability). Builds on orion and substitutes to
# the target, matching the --build-host model of switch-<host> (--builders +
# builders-use-substitutes; the closure never compiles on the 1 GB/aarch64
# target). Node config (hostname from fleet SSOT, erik@2222, per-host magic
# rollback) lives in modules/deploy-rs.nix.
#
# Rollout is canary-first: voyager is the canary (public IP, free, recreatable —
# a bad switch auto-reverts instead of bricking it). Once proven there, the same
# recipe deploys discovery/orion/pathfinder/kepler/archinaut. The legacy
# switch-<host>/deploy recipes stay as the escape hatch — deploy-rs adds an
# output + a recipe, it changes no host config, so reverting is "use switch-X".
#
# Pinned from the flake input (NOT `nix run github:…`) so the deployed tool
# matches flake.lock. archinaut (aarch64) activates fine here: activate.nixos is
# selected per host system in the module.
#   just deploy-rs voyager
deploy-rs target:
    BUILDERS="$(just _builders {{target}})"; \
    nix run .#deploy-rs -- --skip-checks .#{{target}} \
        -- --option builders "$BUILDERS" \
           --option builders-use-substitutes true \
           --max-jobs 0

# Like deploy-rs, but --boot: set the new generation as the NEXT-BOOT target
# WITHOUT live-activating. For GPU/driver hosts (kepler, discovery) where an
# nvidia driver bump in the closure would mismatch the running kernel module on a
# live switch — the running services stay up until you reboot into the new gen
# (kernel + driver then match). No magic rollback (it's boot-not-activate), so
# reboot deliberately. Follow with: ssh -p 2222 erik@<ip> sudo systemctl reboot
deploy-rs-boot target:
    BUILDERS="$(just _builders {{target}})"; \
    nix run .#deploy-rs -- --skip-checks --boot .#{{target}} \
        -- --option builders "$BUILDERS" \
           --option builders-use-substitutes true \
           --max-jobs 0

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

# Validate the declared disko /dev/sda layout end-to-end: partition, install, and
# boot in a throwaway VM (does NOT touch Oracle). This is the same install path
# `deploy-voyager` runs. Complements voyager-vm-* which exercise runtime/compose
# on the build.vm ephemeral disk — vm-test is the only thing that exercises disko.
voyager-vm-test:
    nix run github:nix-community/nixos-anywhere -- --vm-test --flake .#voyager

# Build the Voyager VM runner locally, offloading compilation to Orion when useful.
voyager-vm-build:
    nix build .#nixosConfigurations.voyager.config.system.build.vm --show-trace \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true

# Start a detached Voyager validation VM on Orion. Disk and logs live in /scratch.
voyager-vm-start:
    #!/usr/bin/env bash
    set -euo pipefail
    just voyager-vm-build
    VM_PATH="$(readlink -f result)"
    VM_RUNNER=""
    for candidate in "$VM_PATH"/bin/*; do VM_RUNNER="$candidate"; break; done
    test -n "$VM_RUNNER"
    nix copy --no-check-sigs --to "ssh-ng://erik@{{ip_orion}}" "$VM_PATH"
    remote_script='
    set -euo pipefail
    # If any setup step fails, tear down the tap + NAT rules we just added so a
    # partial start does not orphan host network state.
    cleanup() {
      sudo iptables -t nat -D POSTROUTING -s 10.88.0.0/24 -o enp4s0 -j MASQUERADE 2>/dev/null || true
      sudo iptables -D FORWARD -i voyager-vm-tap -o enp4s0 -j ACCEPT 2>/dev/null || true
      sudo iptables -D FORWARD -i enp4s0 -o voyager-vm-tap -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
      sudo ip link delete voyager-vm-tap 2>/dev/null || true
    }
    trap cleanup ERR
    if ! ip link show voyager-vm-tap >/dev/null 2>&1; then
      sudo ip tuntap add dev voyager-vm-tap mode tap user erik
    fi
    sudo ip addr replace 10.88.0.1/24 dev voyager-vm-tap
    sudo ip link set voyager-vm-tap up
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
    sudo iptables -t nat -C POSTROUTING -s 10.88.0.0/24 -o enp4s0 -j MASQUERADE 2>/dev/null || \
      sudo iptables -t nat -A POSTROUTING -s 10.88.0.0/24 -o enp4s0 -j MASQUERADE
    sudo iptables -C FORWARD -i voyager-vm-tap -o enp4s0 -j ACCEPT 2>/dev/null || \
      sudo iptables -A FORWARD -i voyager-vm-tap -o enp4s0 -j ACCEPT
    sudo iptables -C FORWARD -i enp4s0 -o voyager-vm-tap -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
      sudo iptables -A FORWARD -i enp4s0 -o voyager-vm-tap -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    mkdir -p /scratch/voyager-vm
    if [ -f /scratch/voyager-vm/vm.pid ] && kill -0 "$(cat /scratch/voyager-vm/vm.pid)" 2>/dev/null; then
      echo ":: Voyager VM already running"
      exit 0
    fi
    cd /scratch/voyager-vm
    nohup env NIX_DISK_IMAGE=/scratch/voyager-vm/voyager.qcow2 "$VM_RUNNER" \
      > /scratch/voyager-vm/console.log 2>&1 < /dev/null &
    echo $! > /scratch/voyager-vm/vm.pid
    echo ":: Voyager VM started on Orion"
    echo ":: SSH: ssh -p 2222 erik@10.88.0.2 from Orion"
    echo ":: Restic REST: http://10.88.0.2:8000 from Orion"
    '
    printf "%s" "$remote_script" | ssh -p 2222 erik@{{ip_orion}} "env VM_RUNNER='$VM_RUNNER' bash -s"

voyager-vm-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    remote_script='
    set -euo pipefail
    if [ -f /scratch/voyager-vm/vm.pid ] && kill -0 "$(cat /scratch/voyager-vm/vm.pid)" 2>/dev/null; then
      kill "$(cat /scratch/voyager-vm/vm.pid)"
      echo ":: Voyager VM stopped"
    else
      echo ":: Voyager VM is not running"
    fi
    sudo iptables -t nat -D POSTROUTING -s 10.88.0.0/24 -o enp4s0 -j MASQUERADE 2>/dev/null || true
    sudo iptables -D FORWARD -i voyager-vm-tap -o enp4s0 -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -i enp4s0 -o voyager-vm-tap -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    sudo ip link delete voyager-vm-tap 2>/dev/null || true
    '
    printf "%s" "$remote_script" | ssh -p 2222 erik@{{ip_orion}} bash -s

voyager-vm-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    remote_script='
    set -euo pipefail
    for _ in $(seq 1 60); do
      if ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/voyager-vm-known_hosts -p 2222 erik@10.88.0.2 "hostname"; then
        # podman-compose-offsite is a rootless *user* unit; query it in --user
        # scope. It can take minutes to come up, so report it, do not gate on it.
        ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/voyager-vm-known_hosts -p 2222 erik@10.88.0.2 \
          "systemctl --user is-active podman-compose-offsite.service || true"
        code=$(curl -sS -o /dev/null -w "%{http_code}" http://10.88.0.2:8000/ || true)
        echo ":: restic-rest HTTP status: $code"
        exit 0
      fi
      sleep 5
    done
    echo ":: Voyager VM did not become reachable" >&2
    exit 1
    '
    printf "%s" "$remote_script" | ssh -p 2222 erik@{{ip_orion}} bash -s

# ── drtest deploy-rs proof-of-concept VM ─────────────────
# Throwaway QEMU VM on orion used to prove deploy-rs magic rollback end-to-end.
# Uses QEMU usermode networking: orion:2224 → VM:2222 (sshd). No tap/iptables.
# deploy-rs node: drtest (see modules/deploy-rs.nix). After testing, run drtest-vm-stop.

# Build the drtest VM on orion (x86_64), copy closure back locally.
drtest-vm-build:
    nix build .#nixosConfigurations.drtest.config.system.build.vm --show-trace \
        --option builders "{{orion_builder}}" \
        --option builders-use-substitutes true

# Start a detached drtest VM on orion. Disk lives in /scratch/drtest-vm/.
drtest-vm-start:
    #!/usr/bin/env bash
    set -euo pipefail
    just drtest-vm-build
    VM_PATH="$(readlink -f result)"
    VM_RUNNER=""
    for candidate in "$VM_PATH"/bin/*; do VM_RUNNER="$candidate"; break; done
    test -n "$VM_RUNNER"
    nix copy --no-check-sigs --to "ssh-ng://erik@{{ip_orion}}" "$VM_PATH"
    remote_script='
    set -euo pipefail
    mkdir -p /scratch/drtest-vm
    if [ -f /scratch/drtest-vm/vm.pid ] && kill -0 "$(cat /scratch/drtest-vm/vm.pid)" 2>/dev/null; then
      echo ":: drtest VM already running (pid $(cat /scratch/drtest-vm/vm.pid))"
      exit 0
    fi
    cd /scratch/drtest-vm
    # QEMU usermode: host port 2224 → guest port 2222 (sshd). The -netdev user
    # hostfwd is passed via NIX_QEMU_OPTS so the vm runner picks it up.
    # The vm runner script already sets -netdev user,id=user.0,... via vmVariant;
    # those networkingOptions replace the default, so hostfwd is baked in.
    nohup env NIX_DISK_IMAGE=/scratch/drtest-vm/drtest.qcow2 "$VM_RUNNER" \
      > /scratch/drtest-vm/console.log 2>&1 < /dev/null &
    echo $! > /scratch/drtest-vm/vm.pid
    echo ":: drtest VM started on Orion (pid $!)"
    echo ":: Hostfwd: orion:2224 → VM:2222"
    echo ":: SSH from orion: ssh -p 2224 erik@127.0.0.1"
    echo ":: SSH from laptop: ssh -p 2224 erik@{{ip_orion}}"
    '
    printf "%s" "$remote_script" | ssh -p 2222 erik@{{ip_orion}} "env VM_RUNNER='$VM_RUNNER' bash -s"

# Stop the drtest VM on orion and clean up the scratch disk.
drtest-vm-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    remote_script='
    set -euo pipefail
    if [ -f /scratch/drtest-vm/vm.pid ] && kill -0 "$(cat /scratch/drtest-vm/vm.pid)" 2>/dev/null; then
      kill "$(cat /scratch/drtest-vm/vm.pid)"
      rm -f /scratch/drtest-vm/vm.pid
      echo ":: drtest VM stopped"
    else
      echo ":: drtest VM is not running"
    fi
    rm -f /scratch/drtest-vm/drtest.qcow2
    echo ":: scratch disk removed"
    '
    printf "%s" "$remote_script" | ssh -p 2222 erik@{{ip_orion}} bash -s

# Wait until the drtest VM's SSH is reachable (from laptop via orion:2224).
drtest-vm-wait:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ":: Waiting for drtest VM SSH on {{ip_orion}}:2224 ..."
    for i in $(seq 1 60); do
      if ssh -o BatchMode=yes -o ConnectTimeout=3 \
             -o StrictHostKeyChecking=accept-new \
             -o UserKnownHostsFile=/tmp/drtest-vm-known_hosts \
             -p 2224 erik@{{ip_orion}} "hostname" 2>/dev/null; then
        echo ":: drtest VM is reachable"
        exit 0
      fi
      echo "  attempt $i/60..."
      sleep 5
    done
    echo ":: drtest VM did not become reachable within 5m" >&2
    exit 1

# SSH directly into the drtest VM (via orion:2224).
drtest-vm-ssh:
    ssh -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/tmp/drtest-vm-known_hosts \
        -p 2224 erik@{{ip_orion}}

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
    # Builder spec fields: uri system sshkey maxjobs speed features mandatory.
    # maxjobs=16 is the key one — omitting it defaults to 1 (serial builds on a
    # single core of orion's 32, the old bottleneck). Redundant once orion has
    # aarch64 in its persistent buildMachines entry + the laptop is rebuilt, but
    # harmless and works immediately without a laptop switch.
    nix build .#nixosConfigurations.{{target}}.config.system.build.sdImage \
        --builders 'ssh-ng://erik@{{ip_orion}}?ssh-key=/root/.ssh/nix-builder aarch64-linux - 16 4 big-parallel -' \
        --max-jobs 0 --show-trace --out-link result-{{target}}-sd
    @echo ":: image at result-{{target}}-sd/sd-image/ — flash with:"
    @echo "   zstd -dc result-{{target}}-sd/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M oflag=direct status=progress conv=fsync"

# Flash the built SD image AND inject the sops age key in one step, so a
# freshly-flashed card boots straight onto WiFi — no manual mount-and-copy.
#
# Why this is needed: archinaut is WiFi-only and its PSK is a sops secret
# (wifi_secrets → $psk_quewifi) decrypted using the age key at
# sops.age.keyFile (modules/services/sops.nix). first-boot.nix's
# distributeSopsKey activation script expects that key staged at
# /var/lib/sops-staging/age-keys.txt — the nixos-anywhere `provision` recipe
# seeds it via --extra-files, but the sd-image build has no such mechanism,
# so a card flashed straight from `build-archinaut-sd` boots with no age key,
# sops can't decrypt the PSK, and WiFi never comes up (unreachable Pi).
# This recipe flashes, then mounts the rootfs partition and drops the key in
# — post-flash injection, deliberately NOT baked into the .img artifact
# (that's a build output; a baked-in secret would leak into it).
#
# device = e.g. /dev/sdX — required, no default (never guess a disk to dd to).
flash-archinaut-sd device target="archinaut":
    #!/usr/bin/env bash
    set -euo pipefail
    IMG=$(ls result-{{target}}-sd/sd-image/*.img.zst 2>/dev/null | head -1)
    if [ -z "$IMG" ]; then
        echo ":: No image found at result-{{target}}-sd/sd-image/ — run: just build-archinaut-sd"
        exit 1
    fi
    case "{{device}}" in
        /dev/*) ;;
        *) echo ":: refusing — device must look like /dev/sdX, got: {{device}}"; exit 1 ;;
    esac
    if mount | grep -q "^{{device}}[0-9]* on / "; then
        echo ":: refusing — {{device}} looks like the system disk"
        exit 1
    fi

    echo ":: unmounting any mounted partitions of {{device}}"
    for part in {{device}}*[0-9]; do
        [ -e "$part" ] && sudo umount "$part" 2>/dev/null || true
    done

    echo ":: flashing $IMG → {{device}}"
    zstd -dc "$IMG" | sudo dd of={{device}} bs=4M oflag=direct status=progress conv=fsync
    sudo partprobe {{device}}
    sleep 2

    ROOT_PART="{{device}}2"
    MNT=$(mktemp -d)
    echo ":: mounting $ROOT_PART (NIXOS_SD rootfs) at $MNT"
    sudo mount "$ROOT_PART" "$MNT"

    echo ":: injecting sops age key at /var/lib/sops-staging/age-keys.txt"
    sudo mkdir -p "$MNT/var/lib/sops-staging"
    sudo cp ~/.config/sops/age/keys.txt "$MNT/var/lib/sops-staging/age-keys.txt"
    sudo chown 0:0 "$MNT/var/lib/sops-staging/age-keys.txt"
    sudo chmod 600 "$MNT/var/lib/sops-staging/age-keys.txt"
    sudo test -s "$MNT/var/lib/sops-staging/age-keys.txt"

    sync
    sudo umount "$MNT"
    rmdir "$MNT"

    echo ":: done — card ready, insert into the Pi and power it on."
    echo ":: reminder — two known gotchas after reflash:"
    echo "   1. Reflash = new tailscale identity → new tailnet IP. Update the"
    echo "      archinaut entry in homelab-iac's tailnet ACL hosts-map or"
    echo "      log-shipping (vector→discovery:3100) won't match."
    echo "   2. If klipper shows \"mcu 'mcu': Serial connection closed\", power on"
    echo "      the printer mainboard, then:"
    echo "      curl -X POST http://<pi>:7125/printer/firmware_restart"

# Deploy archinaut: evaluate locally, build aarch64 on orion, push to the Pi.
switch-archinaut:
    just deploy-rs archinaut

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

# Git is the single source→host path for servarr stacks. Each host's
# servarr-pull service does `git fetch + reset --hard origin/main` (see
# modules/server/orchestration.nix). rsync delivery was retired 2026-06-29: it
# dirtied the git tree and silently broke servarr-pull's old ff-only pull, so
# hosts stopped receiving commits. New flow:
#   1. edit references/repos/servarr/machines/<host>/...
#   2. just prep-servarr            # refresh generated mirrors (SOUL.md)
#   3. (in the servarr repo) git commit + push origin main
#   4. just pull-servarr <host>     # host fetches + resets to origin/main
#   5. just kick-stack <host> <stack>   # recreate containers whose files changed

# Refresh generated files in the servarr tree before you commit. Today: mirror
# the canonical hermes SOUL.md (owned here) into the discovery stack so the
# deployed copy can't drift. Edit modules/hosts/discovery/homelab-SOUL.md, never
# the mirror. Run this, then commit + push in the servarr repo.
prep-servarr:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="$(readlink -f references/repos/servarr)"
    cp modules/hosts/discovery/homelab-SOUL.md \
       "$SRC/machines/discovery/config/hermes-agent/SOUL.md"
    echo ":: Mirrored homelab-SOUL.md → servarr/machines/discovery/config/hermes-agent/SOUL.md"
    echo ":: Now commit + push in the servarr repo, then: just pull-servarr <host>"

# Trigger a host to sync its servarr clone to a branch (fetch + reset --hard)
# and re-decrypt .env.sops. Run after committing + pushing servarr changes. The
# ref MUST exist on origin — the host resets to it; any local host edits are
# discarded by design (git is authoritative). Branch defaults to `main`; pass a
# feature branch to deploy it for testing, then `just pull-servarr <host>` (no
# branch) to return the host to main. The branch sticks across reboots via an
# untracked `.deploy-branch` pointer.
#   just pull-servarr discovery                 # → origin/main
#   just pull-servarr discovery feature/new-svc # → origin/feature/new-svc
pull-servarr target branch="main":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    echo ":: Pointing {{target}} servarr clone at origin/{{branch}} and pulling..."
    ssh -p 2222 erik@"$IP" "printf '%s\n' {{branch}} > /home/erik/servarr/.deploy-branch"
    # daemon-reload picks up a freshly-deployed unit; restart (not start) is
    # required because servarr-pull is RemainAfterExit — `start` no-ops once it
    # has run, so the reset --hard would never re-fire.
    ssh -p 2222 erik@"$IP" "systemctl --user daemon-reload && systemctl --user restart servarr-pull.service"
    ssh -p 2222 erik@"$IP" "systemctl --user status servarr-pull.service --no-pager -n15"
    echo ":: {{target}} now on origin/{{branch}}. Recreate changed stacks: just kick-stack {{target}} <stack>"

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

# After pulling, kick the compose stack on the remote host:
#   just kick-stack kepler ai-serving
kick-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    # restart (not start): the unit is RemainAfterExit, so `start` no-ops once
    # active and would not re-run `compose up -d --remove-orphans`.
    ssh -p 2222 erik@$IP "systemctl --user restart podman-compose-{{stack}}.service"
    ssh -p 2222 erik@$IP "systemctl --user status podman-compose-{{stack}}.service --no-pager -n10"

# Remote ai-serving health probe (runs from your workstation, hits kepler:<ports>)
ai-kepler-health:
    @just verify-port kepler {{ip_kepler}} 8001
    @just verify-port kepler {{ip_kepler}} 8085
    @just verify-port kepler {{ip_kepler}} 8087
    @just verify-port kepler {{ip_kepler}} 9000
    @just verify-port kepler {{ip_kepler}} 10200

# Retrieval-model status plus bounded recent logs; no secret output.
ai-kepler-retrieval-health:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" 'for name in slm-bge-m3 slm-bge-reranker; do docker inspect --format=":: {{"{{"}}.Name{{"}}"}} state={{"{{"}}.State.Status{{"}}"}} health={{"{{"}}if .State.Health{{"}}"}}{{"{{"}}.State.Health.Status{{"}}"}}{{"{{"}}else{{"}}"}}none{{"{{"}}end{{"}}"}}" "$name"; docker logs --tail 15 "$name" 2>&1; done'

ai-kepler-gpu-health:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" 'timeout 15s nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free --format=csv,noheader; timeout 15s nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader'

# Reset the embedder CUDA context with the competing reranker stopped.
ai-kepler-embed-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" 'docker stop slm-bge-reranker >/dev/null 2>&1 || true; docker restart slm-bge-m3 >/dev/null; for _ in $(seq 1 60); do health=$(docker inspect --format="{{"{{"}}if .State.Health{{"}}"}}{{"{{"}}.State.Health.Status{{"}}"}}{{"{{"}}else{{"}}"}}none{{"{{"}}end{{"}}"}}" slm-bge-m3); if [ "$health" = healthy ]; then echo ":: slm-bge-m3 healthy"; exit 0; fi; sleep 2; done; echo ":: slm-bge-m3 failed to become healthy" >&2; exit 1'

# Clear queued rerank work, then wait through the CPU model warmup.
ai-kepler-reranker-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" 'docker restart slm-bge-reranker >/dev/null; for _ in $(seq 1 180); do health=$(docker inspect --format="{{"{{"}}if .State.Health{{"}}"}}{{"{{"}}.State.Health.Status{{"}}"}}{{"{{"}}else{{"}}"}}none{{"{{"}}end{{"}}"}}" slm-bge-reranker); if [ "$health" = healthy ]; then echo ":: slm-bge-reranker healthy"; exit 0; fi; sleep 2; done; echo ":: slm-bge-reranker failed to become healthy" >&2; exit 1'

# Activate the generation staged by `just switch-kepler`, then wait for SSH.
reboot-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} sudo systemctl reboot || true
    echo ":: waiting for kepler to stop..."
    for _ in $(seq 1 30); do
        if ! ssh -p 2222 -o ConnectTimeout=2 erik@{{ip_kepler}} true 2>/dev/null; then
            break
        fi
        sleep 1
    done
    echo ":: waiting for kepler to return..."
    for _ in $(seq 1 60); do
        if ssh -p 2222 -o ConnectTimeout=2 erik@{{ip_kepler}} true 2>/dev/null; then
            echo ":: kepler reachable"
            exit 0
        fi
        sleep 2
    done
    echo ":: kepler did not return within 120s" >&2
    exit 1

# Collect sanitized K1 collision evidence. Collector executes from committed
# stdin, writes nothing remotely, and emits only allowlisted runtime metadata.
kepler-recovery-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    collector="modules/hosts/kepler/_collision_recovery_inventory.py"
    remote_sanitizer="modules/hosts/kepler/_collision_recovery_remote.sh"
    evidence_dir=".gsd/evidence/kepler-k1"
    out="$evidence_dir/inventory.json"
    test -f "$collector" -a -f "$remote_sanitizer"
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tmp="$(mktemp "$evidence_dir/.inventory.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} 'bash -s' < "$remote_sanitizer" \
      | python3 "$collector" --remote-input > "$tmp"
    python3 - "$tmp" <<'PY'
    import hashlib
    import json
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    result = json.loads(path.read_text())
    inventory = result["inventory"]
    canonical = (json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()
    actual = hashlib.sha256(canonical).hexdigest()
    if result.get("schema") != "kepler-collision-inventory-v1" or result.get("inventory_sha256") != actual:
        raise SystemExit("inventory envelope/hash validation failed")
    PY
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'inventory=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["inventory_sha256"])' "$out")"

# Resolve only reviewed K1 model artifact paths. The committed helper performs
# read-only traversal and emits no directory listings, contents, or environment.
kepler-recovery-model-paths:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    helper="modules/hosts/kepler/_collision_recovery_model_paths_remote.py"
    evidence_dir=".gsd/evidence/kepler-k1"
    out="$evidence_dir/model-paths.json"
    test -f "$helper"
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tmp="$(mktemp "$evidence_dir/.model-paths.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} 'tool=$(command -v kepler-collision-recovery-inventory); interpreter=$(head -n1 "$tool"); interpreter=${interpreter#\#!}; exec "$interpreter" -' < "$helper" > "$tmp"
    python3 - "$tmp" <<'PY'
    import json
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    result = json.loads(path.read_text())
    if result.get("schema") != "kepler-k1-model-paths-v1":
        raise SystemExit("model-path evidence schema validation failed")
    artifacts = result.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != 6:
        raise SystemExit("model-path evidence artifact validation failed")
    PY
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'model_paths=%s\n' "$out"

# Rebuild the locally-owned docs-search image and recreate its service.
rebuild-docs-search:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" \
        "cd /home/erik/servarr/machines/kepler && DOCKER_HOST=unix:///run/user/1000/podman/podman.sock docker-compose --project-name docs-search --env-file .env -f docs-search.yml build docs-search && DOCKER_HOST=unix:///run/user/1000/podman/podman.sock docker-compose --project-name docs-search --env-file .env -f docs-search.yml up -d docs-search"

# Crawl and index the exact Spark docs version through LiteLLM bge-m3.
index-spark-docs version="4.0.1" max_pages="500":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" \
        "cd /home/erik/servarr/machines/kepler && DOCKER_HOST=unix:///run/user/1000/podman/podman.sock docker-compose --project-name docs-search --env-file .env -f docs-search.yml --profile index run --rm docs-indexer spark --version {{version}} --max-pages {{max_pages}}"

# Verify all Hermes role containers and Daedalus MCP registration without
# exposing API keys or decrypted secret contents.
hermes-agents-health:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'for name in hermes-agent hermes-daedalus hermes-argus; do state=$(docker inspect --format="{{"{{"}}.State.Status{{"}}"}}" "$name"); health=$(docker inspect --format="{{"{{"}}if .State.Health{{"}}"}}{{"{{"}}.State.Health.Status{{"}}"}}{{"{{"}}else{{"}}"}}none{{"{{"}}end{{"}}"}}" "$name"); printf ":: %s state=%s health=%s\n" "$name" "$state" "$health"; test "$state" = running; done; docker exec hermes-daedalus hermes mcp list'

verify-port target ip port:
    @nc -z -w 2 {{ip}} {{port}} && echo ":: {{target}}:{{port}} ✅" || echo ":: {{target}}:{{port}} ❌"

# ── Provisioning (first install) ──────────────────────────
# Method by host class (see docs/proposals/2026-06-30-deploy-rs-as-deploy-standard.md):
#   • RAM-ample host (LAN server, A1 ARM) → `just provision <host> <user@ip[:port]>`
#     (nixos-anywhere; kexec works; disko partitions). Then deploy-rs for switches.
#   • 1 GB x86 Oracle micro (can't kexec) → `just infect-voyager` (nixos-infect).
#   • Raspberry Pi (archinaut) → SD image: `just build-archinaut-sd`, dd, first boot.

# Provision a NEW remote host: convert a fresh box (cloud Ubuntu entrypoint, or a
# NixOS-ISO installer) to NixOS via nixos-anywhere. Builds the closure on Orion
# (--max-jobs 0 → this machine only orchestrates + the target substitutes from
# Orion's cache), stages the sops age key so first-boot secrets decrypt, and lets
# the host's disko config partition the disk. <target> = user@ip[:port] of the
# installer entrypoint (ubuntu@<ip> for a cloud image, nixos@<ip> for the NixOS
# ISO). WARNING: wipes the target disk. After it lands: set the host IP in
# meta.nix → `just fleet-json` → `just deploy-rs <host>` for subsequent switches.
provision host target:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra-{{host}}/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra-{{host}}/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra-{{host}}/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra-{{host}}' EXIT
    export NIX_CONFIG="builders = {{orion_builder}}
    max-jobs = 0
    builders-use-substitutes = true"
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{host}} \
        --extra-files /tmp/nixos-extra-{{host}} \
        --show-trace \
        {{target}}

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

# telstar first install: convert the Oracle A1 Ubuntu entrypoint to NixOS via
# nixos-anywhere. A1 (12 GB) has the RAM to kexec, unlike the x86 micro — so the
# standard path works (no infect, no image import). Closure builds on Orion
# (aarch64 binfmt); disko + the explicit hardware.nix own the disk, so no
# --generate-hardware-config. Run AFTER the capacity-retry cron creates the
# instance and meta.nix hosts.telstar.ip (+ fleet.json) is set to its public IP.
# WARNING: nixos-anywhere wipes /dev/sda. Entrypoint ubuntu@{{ip_telstar}}:22.
deploy-telstar:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra-telstar/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra-telstar/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra-telstar/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra-telstar' EXIT
    export NIX_CONFIG="builders = {{orion_builder}}
    max-jobs = 0
    builders-use-substitutes = true"
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#telstar \
        --extra-files /tmp/nixos-extra-telstar \
        --show-trace \
        ubuntu@{{ip_telstar}}

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

# Provision voyager by converting the stock Ubuntu cloud image to NixOS IN
# PLACE with nixos-infect, reusing Ubuntu's existing GPT layout (sda1 /, sda16
# /boot, sda15 ESP) — no repartition, no disko. This is the only viable path on
# the 1 GB x86 micro: it can't kexec-install (nixos-anywhere OOMs on
# `kexec --load`) and disko's image builder is broken against the pinned
# nixpkgs. infect installs a minimal NixOS + GRUB-UEFI and reboots; afterwards
# `just switch-voyager root 22` converges to the full flake config (built on
# Orion). 4 GB swap on the Ubuntu entrypoint keeps the infect build off the OOM
# killer. Entrypoint ubuntu@{{ip_voyager}}:22; the SSH session drops on reboot.
#
# (The aarch64 A1 path — nixos-anywhere + disko — lives in git history; restore
# disko + flip hostPlatform to aarch64 if/when A1 capacity lands.)
# noreboot=1 runs infect WITHOUT the final reboot, leaving the box on reachable
# Ubuntu so the generated /etc/nixos can be inspected/hardened (add console=ttyS0,
# verify DHCP) before booting into NixOS the first time.
infect-voyager noreboot="":
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -o StrictHostKeyChecking=accept-new ubuntu@{{ip_voyager}} '
        set -eu
        if ! sudo swapon --show | grep -q /swapfile; then
            sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
            sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
        fi
        curl -fsSL https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect -o /tmp/nixos-infect
        sudo env NIX_CHANNEL=nixos-unstable NO_REBOOT="{{noreboot}}" bash /tmp/nixos-infect
    ' || true
    echo ":: nixos-infect done. noreboot={{noreboot}}"

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

# ── sops age-key off-site escrow (RFC 2026-06-30 §4b) ──────

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
    ssh -p 2222 erik@{{ip_voyager}} 'mkdir -p ~/escrow && chmod 700 ~/escrow'
    scp -P 2222 "$blob" erik@{{ip_voyager}}:~/escrow/age-key.age
    ssh -p 2222 erik@{{ip_voyager}} 'chmod 600 ~/escrow/age-key.age && ls -l ~/escrow/age-key.age'
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
# private key so a re-imaged laptop can reach voyager's PUBLIC-IP SSH and pull
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
    echo "     scp -P 2222 $blob erik@{{ip_voyager}}:~/escrow/ssh-key.age   # secondary copy"
    echo "   Recover: age -d ssh-key.age > id; chmod 600 id; ssh -i id erik@<voyager-public-ip>"

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
    ssh -p 2222 erik@{{ip_voyager}} 'mkdir -p ~/escrow && chmod 700 ~/escrow'
    scp -P 2222 "$tmp/sops-config.tar.gz" erik@{{ip_voyager}}:~/escrow/sops-config.tar.gz
    ssh -p 2222 erik@{{ip_voyager}} 'chmod 600 ~/escrow/sops-config.tar.gz && ls -l ~/escrow/sops-config.tar.gz'
    echo ":: $n encrypted secret files bundled → voyager:~/escrow/sops-config.tar.gz"
