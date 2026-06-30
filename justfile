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

# Build offload to orion (Ryzen 9 5950X) via ssh-ng
orion_builder := "ssh-ng://erik@" + ip_orion + " x86_64-linux,aarch64-linux /root/.ssh/nix-builder 16 2 big-parallel,benchmark,kvm,nixos-test"

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

switch-discovery:
    just deploy discovery {{ip_discovery}} 2222

switch-orion:
    just deploy orion {{ip_orion}} 2222

switch-pathfinder:
    just deploy pathfinder {{ip_pathfinder}} 2222

switch-kepler:
    just deploy kepler {{ip_kepler}} 2222

switch-voyager:
    just deploy voyager {{ip_voyager}} 2222

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

# Audit a host's actual exposure: listening sockets, the live nftables ruleset,
# and Docker/Podman published ports. Docker may rewrite firewall rules
# (https://wiki.nixos.org/wiki/Firewall), so on container hosts the published
# ports are the real attack surface — not just the NixOS firewall config.
# Read-only. Cross-check the output against the intended exposure manifest.
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

deploy-voyager:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/nixos-extra-voyager/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra-voyager/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra-voyager/var/lib/sops-staging/age-keys.txt
    trap 'rm -rf /tmp/nixos-extra-voyager' EXIT
    # Build the closure on Orion, not this laptop: max-jobs=0 forces every
    # derivation onto the remote builder (the 1 GB Oracle target can't build).
    export NIX_CONFIG="builders = {{orion_builder}}
    max-jobs = 0
    builders-use-substitutes = true"
    # Oracle VM nanda-colors: Ubuntu entrypoint is ubuntu@129.148.45.145:22.
    # WARNING: nixos-anywhere will wipe /dev/sda, including the nanda-colors stack.
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#voyager \
        --extra-files /tmp/nixos-extra-voyager \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/voyager/_hw-generated.nix \
        ubuntu@{{ip_voyager}}

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
