profile := "endeavour"

# Host IPs (LAN, SSH port 2222). Endeavour is Tailscale-only (roaming).
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
tailscale_voyager := `jq -r '.hosts.voyager.tailscaleIp' fleet.json`
tailscale_vanguard := `jq -r '.hosts.vanguard.tailscaleIp' fleet.json`

# Build offload to orion (Ryzen 9 5950X) via ssh-ng
orion_builder := "ssh-ng://erik@" + ip_orion + ":2222 i686-linux,x86_64-linux,aarch64-linux /home/erik/.ssh/id_ed25519 16 2 big-parallel,benchmark,kvm,nixos-test"
kepler_builder := "ssh-ng://erik@" + ip_kepler + ":2222 x86_64-linux /home/erik/.ssh/id_ed25519 2 1 big-parallel,benchmark"

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
# tailnet (tailscaleIp, works roaming); Endeavour is read locally; homeassistant
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
    row endeavour "$b" "$([ "$b" = "$target" ] && echo OK || echo DRIFT)"
    for h in $(jq -r '.hosts | keys[] | select(. != "endeavour" and . != "homeassistant")' fleet.json); do
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

# Read-only migration inventory from the roaming Endeavour. Reports metadata and
# public fingerprints only; never prints private key or credential contents.
audit-endeavour-state target="":
    #!/usr/bin/env bash
    set -euo pipefail
    tail_ip=$(jq -r '.hosts.endeavour.tailscaleIp' fleet.json)
    ip="{{target}}"
    [ -n "$ip" ] || ip="$tail_ip"
    tailscale ping -c 3 "$tail_ip"
    for port in 2222 22; do
      timeout 3 bash -c "</dev/tcp/$ip/$port" 2>/dev/null \
        && echo ":: tcp/$port reachable" \
        || echo ":: tcp/$port unreachable"
    done
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new erik@"$ip" 'bash -s' <<'REMOTE'
    set -euo pipefail
    echo ':: ssh files'
    find ~/.ssh -maxdepth 1 -type f -printf '%f\t%m\t%s bytes\n' | sort
    echo ':: public key fingerprints'
    for key in ~/.ssh/*.pub; do
      [ -f "$key" ] && ssh-keygen -lf "$key"
    done
    echo ':: sops age key'
    find ~/.config/sops/age -maxdepth 1 -type f -printf '%f\t%m\t%s bytes\n' 2>/dev/null | sort || true
    echo ':: NetworkManager profile count'
    sudo find /etc/NetworkManager/system-connections -maxdepth 1 -type f -printf '.' 2>/dev/null | wc -c
    echo ':: SSH listener'
    sudo ss -ltnp | grep ':2222' || true
    echo ':: Tailscale self and Endeavour peer'
    tailscale status --json | jq -c '{self:.Self.TailscaleIPs,endeavour:[.Peer[] | select(.HostName == "endeavour") | {ips:.TailscaleIPs,online:.Online,active:.Active}]}'
    tailscale ping -c 3 endeavour || true
    echo ':: firewall rules mentioning SSH or Tailscale'
    if command -v nft >/dev/null; then
      sudo nft list ruleset | grep -Ei -C2 '2222|tailscale' || true
    else
      sudo iptables-save | grep -Ei -C2 '2222|tailscale' || true
    fi
    echo ':: monitors'
    hyprctl monitors -j 2>/dev/null | jq -c '[.[] | {name,description,width,height,refreshRate,x,y,scale,transform}]' || true
    REMOTE

# ── Local System ──────────────────────────────────────────

build target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    nix build --no-link \
        .#nixosConfigurations.{{target}}.config.system.build.toplevel \
        --builders "$BUILDERS" \
        --builders-use-substitutes --max-jobs 0 --show-trace

switch target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 0

builder-preflight target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo ./scripts/builder-preflight.sh "$BUILDERS"

boot target=profile:
    BUILDERS="$(just _builders {{target}})"; \
    sudo nixos-rebuild boot --flake .#{{target}} --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true --max-jobs 0

deploy-ubuntu-work-profile:
    ./scripts/deploy-ubuntu-work-profile.sh

sync-ubuntu-work-brave-settings:
    ./scripts/sync-ubuntu-work-brave-settings.sh

ubuntu-work-warp-connect:
    ssh -o BatchMode=yes -o ConnectTimeout=10 erik@192.168.122.74 'warp-cli --accept-tos connect'

ubuntu-work-define:
    virsh --connect qemu:///system define modules/hosts/endeavour/ubuntu-work-domain.xml

ubuntu-work-view:
    virt-viewer --connect qemu:///system --reconnect --auto-resize=always --attach ubuntu-work

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
        .#nixosConfigurations.archinaut.config.system.build.toplevel \
        .#nixosConfigurations.pathfinder.config.system.build.toplevel \
        .#nixosConfigurations.discovery.config.system.build.toplevel \
        .#nixosConfigurations.orion.config.system.build.toplevel \
        .#nixosConfigurations.kepler.config.system.build.toplevel \
        .#nixosConfigurations.telstar.config.system.build.toplevel \
        .#nixosConfigurations.vanguard.config.system.build.toplevel \
        .#nixosConfigurations.voyager.config.system.build.toplevel \
        --builders '{{orion_builder}} ; {{kepler_builder}}' \
        --builders-use-substitutes --max-jobs 0 --keep-going --show-trace
    nix build --no-link \
        .#nixosConfigurations.endeavour.config.system.build.toplevel \
        --builders '' --show-trace

dry-all:
    just build-all

lint:
    statix check . -c .statix.toml -i '.direnv/*'

fmt:
    nix fmt ./

fmt-check:
    alejandra --check .

test-kindle-release-agent:
    python -m unittest tests/kindle-release-agent/test_agent.py

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
    echo ":: reusable names under host directories"
    while IFS= read -r f; do
        host=$(basename "$(dirname "$f")")
        while IFS= read -r reg; do
            name=${reg##*.}
            case "$name" in
                "$host"-*) ;;
                *) echo "FAIL: $f registers reusable-looking $name under host $host"; fail=1 ;;
            esac
        done < <(grep -hoE 'flake\.modules\.(nixos|home)\.[A-Za-z0-9_-]+' "$f" || true)
    done < <(find modules/hosts -mindepth 2 -maxdepth 2 -name '*.nix' ! -name '_*')
    echo ":: host-prefixed leaves in profiles"
    for host_dir in modules/hosts/*; do
        host=$(basename "$host_dir")
        if grep -nE "m\.(nixos|home)\.${host}-" modules/profiles/*.nix; then
            echo "FAIL: profile imports host-prefixed leaves for $host"; fail=1
        fi
    done
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
    @echo ":: Testing Kindle release agent..."
    just test-kindle-release-agent
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

# Build every flake check except Endeavour from a clean clone on Orion. The ref
# must already be published on origin/main; dirty local work is never copied.
# Orion evaluates/builds and may offload to Kepler. KACE stays on Endeavour.
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
    printf ':: remote non-Endeavour flake checks coordinator=orion commit=%s\n' "$commit"
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
        continue
      fi
      installables+=(".#checks.$system.\"$name\"")
    done <<<"$check_map"
    "$found_endeavour"
    test "${#installables[@]}" -gt 0
    printf ":: building %d non-Endeavour checks\n" "${#installables[@]}"
    exec nix build --no-link --show-trace "${installables[@]}" \
      --option builders "$builders" \
      --option builders-use-substitutes true'
    printf '%s\n' "$remote_script" | ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 \
      erik@"{{ip_orion}}" bash -s -- "$remote_url" "$commit" "$builders_b64"

# Validate/build Endeavour only on Endeavour, where its proprietary KACE
# fixed-output is permitted to exist. No evaluation or build occurs here.
check-endeavour-remote target="endeavour" ref="HEAD":
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch --quiet origin main
    commit="$(git rev-parse --verify "{{ref}}^{commit}")"
    git merge-base --is-ancestor "$commit" refs/remotes/origin/main || {
      echo ":: BLOCKED: $commit is not published on origin/main" >&2
      exit 2
    }
    remote_url="https://github.com/ErikBPF/desktop-nixos.git"
    printf ':: remote Endeavour check target=%s commit=%s\n' "{{target}}" "$commit"
    remote_script='set -euo pipefail
    work=$(mktemp -d)
    trap '\''rm -rf "$work"'\'' EXIT
    git clone --quiet --no-checkout "$1" "$work/repo"
    git -C "$work/repo" checkout --quiet --detach "$2"
    test -z "$(git -C "$work/repo" status --porcelain)"
    cd "$work/repo"
    exec nix build --no-link --show-trace \
      .#checks.x86_64-linux.\"configurations:nixos:endeavour\"'
    printf '%s\n' "$remote_script" | ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 \
      erik@"{{target}}" bash -s -- "$remote_url" "$commit"

# ── Remote Deploy ─────────────────────────────────────────
# Endeavour is Tailscale only (roaming), use: just deploy endeavour <tailscale-ip> 2222

# Remote switches go through deploy-rs (magic rollback + build on Orion). The
# generic `deploy` recipe below stays as the escape hatch (plain nixos-rebuild,
# local build, no rollback) if deploy-rs itself is ever the problem.
switch-discovery:
    just deploy-rs discovery

# Read-only activation-failure evidence for Discovery's AppArmor unit. Fixed
# unit and allowlisted generation links keep this safe for unattended triage.
discovery-apparmor-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      echo ":: generation identity"
      for link in /run/current-system /run/booted-system /nix/var/nix/profiles/system; do
        if [ -e "$link" ]; then
          printf '%s=%s\n' "$link" "$(readlink -f "$link")"
        else
          printf '%s=absent\n' "$link"
        fi
      done
      echo ":: apparmor status"
      sudo systemctl status apparmor.service --no-pager -l || true
      echo ":: apparmor current-boot journal"
      sudo journalctl -b -u apparmor.service --no-pager -n 160 -o short-iso || true
    REMOTE

switch-orion:
    just deploy-rs orion

restart-gemini-herdr:
    ssh gemini 'systemctl --user restart herdr-session-homelab.service && systemctl --user is-active herdr-session-homelab.service'

verify-gemini-herdr:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh gemini 'bash -s' <<'REMOTE'
    set -euo pipefail
    herdr --version
    status=$(herdr integration status)
    opencode=$(grep '^opencode: ' <<<"$status" || true)
    printf '%s\n' "$opencode"
    grep -Fq 'opencode: current (' <<<"$opencode" || {
      echo 'BLOCKED: OpenCode Herdr integration is missing or outdated' >&2
      exit 1
    }
    for unit in herdr-session-homelab.service herdr-session-dataplatform.service; do
      printf '%s=' "$unit"
      systemctl --user is-active "$unit"
    done
    REMOTE

recache-orion:
    ssh -p 2222 erik@{{ip_orion}} 'sudo systemctl start nix-cache-builder.service'

stop-recache-orion:
    ssh -p 2222 erik@{{ip_orion}} 'sudo systemctl stop nix-cache-builder.service'

reboot-orion:
    ssh -p 2222 erik@{{ip_orion}} 'sudo systemctl reboot'

switch-pathfinder:
    just deploy-rs pathfinder

# Read-only evidence gate for Pathfinder's approved 512M -> 2G ESP migration.
# Conservative projection keeps the largest installed kernel + initrd as the
# known-good pair, adds the candidate pair, then requires 25% ESP reserve.
pathfinder-esp-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(jq -r '.hosts.pathfinder.tailscaleIp // .hosts.pathfinder.ip' fleet.json)"
    evidence="/tmp/pathfinder-esp-preflight.txt"
    nix build --no-link \
      .#nixosConfigurations.pathfinder.config.system.build.kernel \
      .#nixosConfigurations.pathfinder.config.system.build.initialRamdisk
    kernel=$(nix eval --raw .#nixosConfigurations.pathfinder.config.system.build.kernel)
    initrd=$(nix eval --raw .#nixosConfigurations.pathfinder.config.system.build.initialRamdisk)
    target_kernel=$(stat -Lc %s "$kernel"/bzImage)
    target_initrd=$(stat -Lc %s "$initrd"/initrd)
    remote=$(ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 erik@"$IP" '
      set -euo pipefail
      total=$(findmnt -bnro SIZE /boot)
      used=$(findmnt -bnro USED /boot)
      gen_dir=/boot/EFI/nixos
      known_kernel=$(find "$gen_dir" -maxdepth 1 -type f -name "*linux*" ! -name "*initrd*" -printf "%s\n" 2>/dev/null | sort -n | tail -1); known_kernel=${known_kernel:-0}
      known_initrd=$(find "$gen_dir" -maxdepth 1 -type f -name "*initrd*" -printf "%s\n" 2>/dev/null | sort -n | tail -1); known_initrd=${known_initrd:-0}
      generation_bytes=$(du -sb "$gen_dir" 2>/dev/null | cut -f1); generation_bytes=${generation_bytes:-0}
      fixed=$((used-generation_bytes)); [ "$fixed" -lt 0 ] && fixed=0
      printf "total=%s\nused=%s\nfixed=%s\nknown_kernel=%s\nknown_initrd=%s\n" "$total" "$used" "$fixed" "$known_kernel" "$known_initrd"
      boot_src=$(findmnt -nro SOURCE /boot)
      crypt_src=$(sudo cryptsetup status cryptroot | sed -n "s/^[[:space:]]*device:[[:space:]]*//p")
      case "$boot_src" in /dev/sda*) ;; *) echo ":: BLOCKED: /boot is $boot_src, expected /dev/sda" >&2; exit 1;; esac
      case "$crypt_src" in /dev/sda*) ;; *) echo ":: BLOCKED: cryptroot is $crypt_src, expected /dev/sda" >&2; exit 1;; esac
      if lsblk -nrpo FSTYPE | grep -qi "ntfs"; then echo ":: BLOCKED: live NTFS filesystem found" >&2; exit 1; fi
      echo ":: disk inventory"
      lsblk -b -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL,SERIAL
      echo ":: mount sources"
      findmnt -R / /boot /home 2>/dev/null || true
      echo ":: failed units"
      systemctl --failed --no-legend || true
    ')
    eval "$(printf '%s\n' "$remote" | sed -n '1,5p')"
    required=$((fixed + known_kernel + known_initrd + target_kernel + target_initrd))
    usable=$((total * 75 / 100))
    projected_reserve=$(((total-required) * 100 / total))
    {
      date --iso-8601=seconds
      printf 'target_kernel=%s\ntarget_initrd=%s\nrequired=%s\nusable_at_25pct_reserve=%s\nprojected_reserve_pct=%s\n' "$target_kernel" "$target_initrd" "$required" "$usable" "$projected_reserve"
      printf '%s\n' "$remote"
    } | tee "$evidence"
    if [ "$required" -gt "$usable" ]; then
      echo ":: MIGRATION REQUIRED: candidate + known-good + 25% reserve does not fit"
    fi
    if [ "$projected_reserve" -lt 50 ]; then echo ":: WARN: projected ESP reserve below 50%"; fi
    touch /tmp/pathfinder-esp-preflight.ok
    echo ":: PASS: $evidence"

# Read-only source-of-truth check before designing Orion's boot-disk-only ESP
# migration. Stable IDs and mount ancestry matter more than /dev/sdX ordering.
orion-disk-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} '
      set -euo pipefail
      echo ":: block devices"
      lsblk -e7 -b -o NAME,PATH,MAJ:MIN,SIZE,TYPE,FSTYPE,FSVER,LABEL,PARTLABEL,UUID,MOUNTPOINTS,MODEL,SERIAL,WWN
      echo ":: mount sources"
      findmnt -R / /boot /home /nix /var/log /opt/models /projects 2>/dev/null || true
      echo ":: stable device IDs"
      for dev in /dev/nvme0n1 /dev/sda /dev/sdb; do
        [ -b "$dev" ] || continue
        printf "%s -> " "$dev"
        udevadm info --query=property --name="$dev" | sed -n "s/^ID_PATH=//p; s/^ID_SERIAL=//p" | paste -sd " | " -
      done
      echo ":: by-id links"
      find /dev/disk/by-id -maxdepth 1 -type l -printf "%f -> %l\n" | sort
      echo ":: filesystems"
      sudo blkid
      echo ":: failed units"
      systemctl --failed --no-legend || true
    '

# Read-only identity/state gate before Kepler's OS-M.2-only migration.
kepler-esp-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      echo ":: block devices"
      lsblk -e7 -b -o NAME,PATH,MAJ:MIN,SIZE,TYPE,FSTYPE,FSVER,LABEL,PARTLABEL,UUID,MOUNTPOINTS,MODEL,SERIAL,WWN
      echo ":: mount sources"
      for mount in / /boot /home /nix /var/log /fast /bulk; do findmnt -nro TARGET,SOURCE,FSTYPE,UUID "$mount" 2>/dev/null || true; done
      echo ":: stable device IDs"
      find /dev/disk/by-id -maxdepth 1 -type l -printf "%f -> %l\n" | sort
      echo ":: zpools"
      sudo zpool status -P
      sudo zpool list -v
      echo ":: active migration/recovery work"
      systemctl list-units --state=activating,running --no-legend | grep -Ei "collision|recovery|postgres|redis|podman|docker|k3s" || true
      pgrep -a -f "collision|recovery|restic|zfs (send|receive)|nixos-anywhere|disko" || true
      echo ":: failed units"
      systemctl --failed --no-legend || true
    '

kepler-esp-graph-proof:
    #!/usr/bin/env bash
    set -euo pipefail
    script=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.kepler.config.system.build.diskoScript \
      --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0 | tail -1)
    expected="ata-TOSHIBA_KSG60ZMV256G_M.2_2280_256GB_58SF70G0F5WP"
    grep -Fq "$expected" "$script"
    forbidden=(KINGSTON ST4000DM004 fast-pool bulk-pool /dev/sda /dev/sdb /dev/sdc /dev/sde /dev/sdf /dev/sdg /dev/sdh /dev/sdi /dev/sdj /dev/sdk /dev/sdl)
    for token in "${forbidden[@]}"; do
      if grep -Fq "$token" "$script"; then
        echo ":: BLOCKED: destructive graph contains $token" >&2
        exit 1
      fi
    done
    devices=$(sed -n 's/^for dev in \(.*\);/\1/p' "$script")
    test "$devices" = "/dev/disk/by-id/$expected"
    echo ":: PASS: destructive graph contains only $devices"

kepler-esp-live-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    marker=/tmp/kepler-esp-backup.ok
    test -f "$marker"
    grep -Fxq 'snapshot=6a5aa2da' "$marker"
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      os=$(readlink -f /dev/disk/by-id/ata-TOSHIBA_KSG60ZMV256G_M.2_2280_256GB_58SF70G0F5WP)
      test "$os" = /dev/sdd
      test "$(findmnt -nro SOURCE /boot)" = /dev/sdd1
      test "$(findmnt -nro SOURCE /)" = "/dev/sdd2[/root]"
      test "$(sudo zpool list -H -o health fast-pool)" = ONLINE
      test "$(sudo zpool list -H -o health bulk-pool)" = ONLINE
      test "$(sudo zpool status -x)" = "all pools are healthy"
      printf "target=%s serial=%s\n" "$os" "$(lsblk -dnro SERIAL "$os")"
      sudo zpool status -x
    '
    echo ":: PASS: live Kepler identities and ZFS health match reviewed migration graph"

deploy-kepler-esp:
    #!/usr/bin/env bash
    set -euo pipefail
    just kepler-esp-live-preflight
    just kepler-esp-graph-proof
    nix build --no-link .#nixosConfigurations.kepler.config.system.build.toplevel \
      --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0 --show-trace
    extra=$(mktemp -d)
    trap 'rm -rf "$extra"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} \
      'sudo tar -C / -cpf - etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub etc/ssh/ssh_host_rsa_key etc/ssh/ssh_host_rsa_key.pub var/lib/tailscale/tailscaled.state home/erik/.config/sops/age/keys.txt' \
      | tar -xpf - -C "$extra"
    chmod 600 "$extra"/etc/ssh/ssh_host_*_key "$extra"/var/lib/tailscale/tailscaled.state "$extra"/home/erik/.config/sops/age/keys.txt
    export NIX_CONFIG="builders = {{orion_builder}}
    max-jobs = 0
    builders-use-substitutes = true"
    echo ":: DESTRUCTIVE: wiping only Toshiba OS M.2 serial 58SF70G0F5WP"
    nix run github:nix-community/nixos-anywhere -- \
      --force-kexec \
      --target-host erik@{{ip_kepler}} \
      --ssh-port 2222 \
      --flake .#kepler \
      --extra-files "$extra" \
      --debug --show-trace

kepler-esp-backup-inventory:
    ssh -p 2222 erik@{{ip_kepler}} "echo ':: OS filesystem'; df -hT / /home; sudo du -xsh /home/erik /etc/ssh /var/lib/tailscale; echo ':: identity files'; sudo find /etc/ssh /var/lib/tailscale -xdev -maxdepth 2 -type f -printf '%p %s bytes\n' | sort; echo ':: user container units'; export XDG_RUNTIME_DIR=/run/user/\$(id -u); systemctl --user list-units --state=activating,running --no-legend | grep -Ei 'podman|container|compose' || true; podman ps --format json | jq -r '.[] | [.Names[0], .Status] | @tsv' || true; echo ':: representative home files'; sudo find /home/erik -xdev -type f -size +0c -printf '%p %s bytes\n' 2>/dev/null | sort -k2nr | sed -n '1,20p'"

# Full encrypted safety snapshot of Kepler's OS-disk state. ZFS datasets are
# excluded by tar --one-file-system and remain on their preserved disks.
backup-kepler-esp-orion:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER="{{ip_kepler}}"
    ORION="{{ip_orion}}"
    samples=(
      "etc/ssh/ssh_host_ed25519_key"
      "var/lib/tailscale/tailscaled.state"
      "home/erik/.config/sops/age/keys.txt"
      "home/erik/ha-train/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors"
    )
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$KEPLER" "sudo test -f '/$sample'"
    done
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$ORION:/projects/backups/kepler-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$ORION -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    hashes=$(mktemp)
    restore=$(mktemp -d)
    quiesced=0
    cleanup() {
      rm -f "$hashes"
      rm -rf "$restore"
      if [ "$quiesced" -eq 1 ]; then
        ssh -p 2222 erik@"$KEPLER" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user start podman-compose-infra.service' || true
      fi
    }
    trap cleanup EXIT
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$KEPLER" "sudo sha256sum '/$sample'" >>"$hashes"
    done
    ssh -p 2222 erik@"$KEPLER" '
      set -euo pipefail
      export XDG_RUNTIME_DIR=/run/user/$(id -u)
      systemctl --user stop podman-compose-infra.service || true
      podman stop --all --time 30
      test -z "$(podman ps -q)"
    '
    quiesced=1
    if ! restic snapshots >/dev/null 2>&1; then restic init; fi
    ssh -p 2222 erik@"$KEPLER" \
      "sudo tar --one-file-system -C / -cpf - home/erik etc/ssh var/lib/tailscale" \
      | restic backup --stdin --stdin-filename kepler-os-state.tar --tag esp-migration
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r 'max_by(.time).short_id')
    test -n "$snapshot" -a "$snapshot" != null
    ssh -p 2222 erik@"$KEPLER" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user start podman-compose-infra.service'
    quiesced=0
    members=()
    for sample in "${samples[@]}"; do members+=("$sample"); done
    restic dump "$snapshot" kepler-os-state.tar | tar -xpf - -C "$restore" "${members[@]}"
    while read -r expected path; do
      relative=${path#/}
      actual=$(sha256sum "$restore/$relative" | awk '{print $1}')
      test "$actual" = "$expected" || { echo ":: BLOCKED: restore mismatch: $relative" >&2; exit 1; }
      printf 'verified=%s sha256=%s\n' "$relative" "$actual"
    done <"$hashes"
    printf 'snapshot=%s\nverified_at=%s\n' "$snapshot" "$(date --iso-8601=seconds)" \
      | tee /tmp/kepler-esp-backup.ok
    echo ":: PASS: encrypted Kepler OS-state snapshot and four-class restore verified"

diagnose-kepler-compose:
    ssh -p 2222 erik@{{ip_kepler}} "export XDG_RUNTIME_DIR=/run/user/\$(id -u); systemctl --user status podman-compose-infra.service --no-pager -l; journalctl --user -u podman-compose-infra.service -b --no-pager -n 120; echo ':: containers'; podman ps -a --format json | jq -r '.[] | [.Names[0], .State, .Status] | @tsv'"

verify-kepler-esp-backup-orion:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER="{{ip_kepler}}"
    ORION="{{ip_orion}}"
    snapshot=6a5aa2da
    samples=(
      "etc/ssh/ssh_host_ed25519_key"
      "var/lib/tailscale/tailscaled.state"
      "home/erik/.config/sops/age/keys.txt"
      "home/erik/ha-train/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors"
    )
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$ORION:/projects/backups/kepler-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$ORION -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    hashes=$(mktemp)
    restore=$(mktemp -d)
    trap 'rm -f "$hashes"; rm -rf "$restore"' EXIT
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$KEPLER" "sudo sha256sum '/$sample'" >>"$hashes"
    done
    restic snapshots "$snapshot" >/dev/null
    members=()
    for sample in "${samples[@]}"; do members+=("$sample"); done
    restic dump "$snapshot" kepler-os-state.tar | tar -xpf - -C "$restore" "${members[@]}"
    while read -r expected path; do
      relative=${path#/}
      actual=$(sha256sum "$restore/$relative" | awk '{print $1}')
      test "$actual" = "$expected" || { echo ":: BLOCKED: restore mismatch: $relative" >&2; exit 1; }
      printf 'verified=%s sha256=%s\n' "$relative" "$actual"
    done <"$hashes"
    printf 'snapshot=%s\nverified_at=%s\n' "$snapshot" "$(date --iso-8601=seconds)" \
      | tee /tmp/kepler-esp-backup.ok
    echo ":: PASS: encrypted Kepler OS-state snapshot and four-class restore verified"

# Restore only Kepler's OS-disk home tree after nixos-anywhere. Host SSH,
# Tailscale, and sops identities are staged separately by deploy-kepler-esp.
restore-kepler-esp-home-orion:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER="{{ip_kepler}}"
    ORION="{{ip_orion}}"
    snapshot=6a5aa2da
    sample="home/erik/ha-train/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors"
    ssh -p 2222 erik@"$KEPLER" '
      set -euo pipefail
      test "$(findmnt -nro SOURCE /home)" = "/dev/sde2[/home]"
      used=$(sudo du -xsb /home/erik | awk "{print \$1}")
      test "$used" -lt 1073741824
      sudo systemctl stop syncthing.service 2>/dev/null || true
      systemctl --user stop podman-compose-infra.service podman-compose-ai-serving.service podman-compose-docs-search.service 2>/dev/null || true
    '
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$ORION:/projects/backups/kepler-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$ORION -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    expected=$(restic dump "$snapshot" kepler-os-state.tar | tar -xOf - "$sample" | sha256sum | awk '{print $1}')
    restic dump "$snapshot" kepler-os-state.tar \
      | ssh -p 2222 erik@"$KEPLER" 'sudo tar -xpf - -C / home/erik'
    actual=$(ssh -p 2222 erik@"$KEPLER" "sudo sha256sum '/$sample'" | awk '{print $1}')
    test "$actual" = "$expected"
    ssh -p 2222 erik@"$KEPLER" '
      set -euo pipefail
      sudo systemctl start syncthing.service 2>/dev/null || true
      systemctl --user start podman-compose-ai-serving.service podman-compose-docs-search.service 2>/dev/null || true
      sudo du -xsh /home/erik
    '
    printf 'snapshot=%s\nsample=%s\nsha256=%s\nrestored_at=%s\n' \
      "$snapshot" "$sample" "$actual" "$(date --iso-8601=seconds)" \
      | tee /tmp/kepler-esp-restore.ok
    echo ":: PASS: Kepler home restored and representative large file verified"

# Reassert declarative Home Manager links after restoring the mutable home tree.
repair-kepler-after-home-restore:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      sudo systemctl restart home-manager-erik.service
      systemctl --user daemon-reload
      systemctl --user start podman-compose-ai-serving.service podman-compose-docs-search.service
      systemctl --user reset-failed
      sudo systemctl restart syncthing.service
      systemctl --user status podman-compose-ai-serving.service podman-compose-docs-search.service --no-pager -l
    '

diagnose-kepler-home-manager:
    ssh -p 2222 erik@{{ip_kepler}} 'sudo systemctl status home-manager-erik.service --no-pager -l; sudo journalctl -u home-manager-erik.service -b --no-pager -n 160'

verify-kepler-after-esp-migration:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      test "$(findmnt -nro SOURCE /boot)" = /dev/sde1
      test "$(findmnt -nro SOURCE /)" = "/dev/sde2[/root]"
      test "$(findmnt -nro SOURCE /home)" = "/dev/sde2[/home]"
      test "$(sudo zpool status -x)" = "all pools are healthy"
      test "$(sudo zpool list -H -o health fast-pool)" = ONLINE
      test "$(sudo zpool list -H -o health bulk-pool)" = ONLINE
      test "$(sudo du -xsb /home/erik | awk "{print \$1}")" -gt 100000000000
      for unit in sshd tailscaled syncthing nfs-server; do
        sudo systemctl is-active --quiet "$unit" || exit 1
      done
      for unit in \
        podman-compose-infra.service \
        podman-compose-buzz.service \
        podman-compose-monitoring.service \
        podman-compose-sync.service \
        podman-compose-security.service \
        podman-compose-whisper-gpu.service \
        podman-compose-qwen4b-gpu.service; do
        systemctl --user is-active --quiet "$unit" || exit 1
      done
      ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
      tailscale status --self
      podman ps --format json | jq -r ".[] | [.Names[0], .Status] | @tsv"
      echo ":: failed system units"
      systemctl --failed --no-legend || true
      echo ":: failed user units"
      systemctl --user --failed --no-legend || true
    '

orion-esp-graph-proof:
    #!/usr/bin/env bash
    set -euo pipefail
    script=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.orion-esp-installer.config.system.build.diskoScript | tail -1)
    expected="nvme-Force_MP510_19458242000129183963"
    grep -Fq "$expected" "$script"
    forbidden=(
      /dev/sda /dev/sdb
      SanDisk_SSD_PLUS_480GB_193181805834
      KINGSTON_SV300S37A480G_50026B724709FD21
      5001b448b8d96bc1 50026b724709fd21
    )
    for token in "${forbidden[@]}"; do
      if grep -Fq "$token" "$script"; then
        echo ":: BLOCKED: destructive graph contains $token" >&2
        exit 1
      fi
    done
    devices=$(sed -n 's/^for dev in \(.*\);/\1/p' "$script")
    test "$devices" = "/dev/disk/by-id/$expected"
    echo ":: PASS: destructive graph contains only $devices"

# Fail-closed live-host identity gate immediately before Orion's NVMe-only wipe.
orion-esp-live-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} '
      set -euo pipefail
      nvme=$(readlink -f /dev/disk/by-id/nvme-Force_MP510_19458242000129183963)
      test "$nvme" = /dev/nvme0n1
      test "$(findmnt -nro SOURCE /boot)" = /dev/nvme0n1p1
      test "$(findmnt -nro SOURCE /)" = "/dev/nvme0n1p2[/root]"
      test "$(findmnt -nro UUID /projects)" = d4511ef9-7f62-4f0f-86d2-ee015344c289
      test "$(findmnt -nro UUID /opt/models)" = 88a7f0d3-2fa2-4354-a4cd-8cab451dce85
      printf "target=%s serial=%s\n" "$nvme" "$(lsblk -dnro SERIAL "$nvme")"
      for mount in /boot / /projects /opt/models; do
        findmnt -nro TARGET,SOURCE,FSTYPE,UUID "$mount"
      done
    '
    echo ":: PASS: live Orion identities match the reviewed migration graph"

# Approved Orion migration: wipe only the Force MP510 NVMe via force-kexec.
# The SATA filesystems are mounted by UUID but absent from the disko graph.
deploy-orion-esp:
    #!/usr/bin/env bash
    set -euo pipefail
    marker=/tmp/orion-esp-backup.ok
    test -f "$marker" || { echo ":: BLOCKED: missing $marker" >&2; exit 1; }
    age=$(( $(date +%s) - $(stat -c %Y "$marker") ))
    test "$age" -le 86400 || { echo ":: BLOCKED: stale $marker" >&2; exit 1; }
    grep -Eq '^snapshot=[0-9a-f]+$' "$marker"
    just orion-esp-live-preflight
    just orion-esp-graph-proof
    nix build --no-link \
      .#nixosConfigurations.orion-esp-installer.config.system.build.toplevel \
      --builders "{{kepler_builder}}" \
      --builders-use-substitutes --max-jobs 0 --show-trace
    extra=$(mktemp -d)
    trap 'rm -rf "$extra"' EXIT
    mkdir -p "$extra/var/lib/sops-staging"
    cp ~/.config/sops/age/keys.txt "$extra/var/lib/sops-staging/age-keys.txt"
    chmod 600 "$extra/var/lib/sops-staging/age-keys.txt"
    export NIX_CONFIG="builders = {{kepler_builder}}
    max-jobs = 0
    builders-use-substitutes = true"
    echo ":: DESTRUCTIVE: wiping only Force MP510 NVMe serial 19458242000129183963"
    nix run github:nix-community/nixos-anywhere -- \
      --force-kexec \
      --target-host erik@{{ip_orion}} \
      --ssh-port 2222 \
      --flake .#orion-esp-installer \
      --extra-files "$extra" \
      --debug --show-trace
    echo ":: preserved mounts"
    nix eval --json .#nixosConfigurations.orion-esp-installer.config.fileSystems \
      --apply 'fs: { models = fs."/opt/models"; projects = fs."/projects"; }' \
      | jq '{models: {device: .models.device, fsType: .models.fsType}, projects: {device: .projects.device, fsType: .projects.fsType, options: .projects.options}}'

orion-home-backup-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} '
      set -euo pipefail
      echo ":: root/home usage"
      df -hT / /home
      sudo du -xsh /home/erik
      echo ":: bootstrap credential"
      find /home/erik/.config/sops/age -xdev -type f -printf "%P %s bytes\n" 2>/dev/null || true
      echo ":: dotfile candidates"
      find /home/erik -xdev -maxdepth 2 -type f -name ".*" -size +0c -printf "%P %s bytes\n" 2>/dev/null | sed -n "1,10p" || true
      echo ":: document candidates"
      find /home/erik/Documents -xdev -type f -size +0c -printf "%P %s bytes\n" 2>/dev/null | sed -n "1,10p" || true
      echo ":: large-file candidates"
      find /home/erik -xdev -type f -size +100M -printf "%P %s bytes\n" 2>/dev/null | sort -k2nr | sed -n "1,10p" || true
      echo ":: excluded nested mounts"
      findmnt -R /home/erik 2>/dev/null || true
    '

# Full encrypted NVMe-home safety snapshot plus one-pass selective restore of
# four evidence classes. SATA mounts are excluded by tar --one-file-system.
backup-orion-home-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    ORION="{{ip_orion}}"
    KEPLER="{{ip_kepler}}"
    samples=(
      ".config/sops/age/keys.txt"
      ".pulse-cookie"
      "Documents/erik/desktop-nixos/flake.nix"
      "Documents/erik/ha-agent/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors"
    )
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$ORION" "test -f '/home/erik/$sample'" || {
        echo ":: BLOCKED: missing /home/erik/$sample" >&2
        exit 1
      }
    done
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/orion-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() { nix shell nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"; }
    if ! restic snapshots >/dev/null 2>&1; then restic init; fi
    hashes=$(mktemp)
    restore=$(mktemp -d)
    trap 'rm -f "$hashes"; rm -rf "$restore"' EXIT
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$ORION" "sha256sum '/home/erik/$sample'" >>"$hashes"
    done
    ssh -p 2222 erik@"$ORION" "sudo tar --one-file-system -C /home/erik -cpf - ." \
      | restic backup --stdin --stdin-filename orion-home.tar --tag esp-migration
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r 'max_by(.time).short_id')
    test -n "$snapshot" -a "$snapshot" != null
    members=()
    for sample in "${samples[@]}"; do members+=("./$sample"); done
    restic dump "$snapshot" orion-home.tar | tar -xpf - -C "$restore" "${members[@]}"
    while read -r expected path; do
      relative=${path#/home/erik/}
      actual=$(sha256sum "$restore/$relative" | awk '{print $1}')
      test "$actual" = "$expected" || { echo ":: BLOCKED: restore mismatch: $relative" >&2; exit 1; }
      printf 'verified=%s sha256=%s\n' "$relative" "$actual"
    done <"$hashes"
    printf 'snapshot=%s\nverified_at=%s\n' "$snapshot" "$(date --iso-8601=seconds)" \
      | tee /tmp/orion-esp-backup.ok
    echo ":: PASS: encrypted Orion snapshot and four-class restore verified"

# Verify the latest Orion ESP snapshot without uploading the full home again.
# Useful when the transfer completed but the post-backup restore was interrupted.
verify-orion-home-backup-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    ORION="{{ip_orion}}"
    KEPLER="{{ip_kepler}}"
    samples=(
      ".config/sops/age/keys.txt"
      ".pulse-cookie"
      "Documents/erik/desktop-nixos/flake.nix"
      "Documents/erik/ha-agent/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors"
    )
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/orion-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() { nix shell nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"; }
    hashes=$(mktemp)
    restore=$(mktemp -d)
    trap 'rm -f "$hashes"; rm -rf "$restore"' EXIT
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$ORION" "sha256sum '/home/erik/$sample'" >>"$hashes"
    done
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r 'max_by(.time).short_id')
    test -n "$snapshot" -a "$snapshot" != null
    members=()
    for sample in "${samples[@]}"; do members+=("./$sample"); done
    restic dump "$snapshot" orion-home.tar | tar -xpf - -C "$restore" "${members[@]}"
    while read -r expected path; do
      relative=${path#/home/erik/}
      actual=$(sha256sum "$restore/$relative" | awk '{print $1}')
      test "$actual" = "$expected" || { echo ":: BLOCKED: restore mismatch: $relative" >&2; exit 1; }
      printf 'verified=%s sha256=%s\n' "$relative" "$actual"
    done <"$hashes"
    printf 'snapshot=%s\nverified_at=%s\n' "$snapshot" "$(date --iso-8601=seconds)" \
      | tee /tmp/orion-esp-backup.ok
    echo ":: PASS: encrypted Orion snapshot and four-class restore verified"

# Restore the verified pre-migration Orion home snapshot from Kepler. Streams
# directly into Orion; no plaintext archive is written to the controller.
restore-orion-home-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    ORION="{{ip_orion}}"
    KEPLER="{{ip_kepler}}"
    marker=/tmp/orion-esp-backup.ok
    test -f "$marker" || { echo ":: BLOCKED: missing $marker" >&2; exit 1; }
    snapshot=$(sed -n 's/^snapshot=//p' "$marker")
    test "$snapshot" = be7f268a || { echo ":: BLOCKED: unexpected snapshot $snapshot" >&2; exit 1; }
    ssh -p 2222 erik@"$ORION" '
      bytes=$(sudo du -x -s --block-size=1 /home/erik | cut -f1)
      echo ":: pre-restore home bytes=$bytes"
      test "$bytes" -lt 104857600 || { echo ":: BLOCKED: home exceeds generated-state threshold" >&2; exit 1; }
    '
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/orion-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() {
      nix shell --builders "{{kepler_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    restic dump "$snapshot" orion-home.tar \
      | ssh -p 2222 erik@"$ORION" 'sudo tar -xpf - -C /home/erik'
    ssh -p 2222 erik@"$ORION" '
      set -euo pipefail
      sudo chown erik:users /home/erik
      sudo systemctl reset-failed home-manager-erik sops-first-boot tailscaled-autoconnect
      sudo systemctl start home-manager-erik
      sudo systemctl start tailscaled-autoconnect
      sudo systemctl reset-failed sops-first-boot
    '
    echo ":: PASS: restored Orion home snapshot $snapshot"

# Stream Pathfinder's full home as one tar object into an encrypted restic repo
# on Kepler, then restore and hash one representative file. No plaintext archive
# lands on either workstation. Passphrase is read silently and never logged.
pathfinder-home-samples:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@"{{ip_pathfinder}}" \
      'find /home/erik/Documents /home/erik/Downloads -xdev -type f -size +0c -printf "%p\n" 2>/dev/null | sed "s|^/home/erik/||" | head -20'

backup-pathfinder-home-kepler sample:
    #!/usr/bin/env bash
    set -euo pipefail
    PATHFINDER="{{ip_pathfinder}}"
    KEPLER="{{ip_kepler}}"
    sample="{{sample}}"
    case "$sample" in /*|*../*) echo ":: BLOCKED: sample must be relative to /home/erik" >&2; exit 1;; esac
    if ! ssh -p 2222 erik@"$PATHFINDER" "test -f '/home/erik/$sample'"; then
      echo ":: BLOCKED: /home/erik/$sample is not a regular file" >&2
      echo ":: choose one with: just pathfinder-home-samples" >&2
      exit 1
    fi
    read -rsp "Restic repository passphrase: " RESTIC_PASSWORD; echo
    export RESTIC_PASSWORD
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/pathfinder-esp"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() { nix shell nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"; }
    if ! restic snapshots >/dev/null 2>&1; then restic init; fi
    source_hash=$(ssh -p 2222 erik@"$PATHFINDER" "sha256sum '/home/erik/$sample'" | awk '{print $1}')
    test -n "$source_hash"
    ssh -p 2222 erik@"$PATHFINDER" "sudo tar --ignore-failed-read --one-file-system -C /home/erik -cpf - ." \
      | restic backup --stdin --stdin-filename pathfinder-home.tar --tag esp-migration
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r 'max_by(.time).short_id')
    test -n "$snapshot" -a "$snapshot" != null
    restored_hash=$(restic dump "$snapshot" pathfinder-home.tar \
      | tar -xOf - "./$sample" | sha256sum | awk '{print $1}')
    test "$source_hash" = "$restored_hash"
    printf 'snapshot=%s\nsample=%s\nsha256=%s\nverified_at=%s\n' "$snapshot" "$sample" "$source_hash" "$(date --iso-8601=seconds)" \
      | tee /tmp/pathfinder-esp-backup.ok
    echo ":: PASS: encrypted Kepler snapshot and representative restore verified"

# Approved destructive Pathfinder reinstall. Requires fresh evidence markers;
# passphrase is supplied through a mode-0600 temp file to nixos-anywhere.
pathfinder-installer-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    info=$(ssh -p 22 -o BatchMode=yes -o ConnectTimeout=8 nixos@"{{ip_pathfinder}}" \
      'printf "host=%s\nroot=%s\n" "$(hostname)" "$(findmnt -nro SOURCE /)"')
    printf '%s\n' "$info"
    root=$(printf '%s\n' "$info" | sed -n 's/^root=//p')
    case "$root" in /dev/mapper/cryptroot*|/dev/sda*)
      echo ":: BLOCKED: port 22 appears to be installed Pathfinder, not installer media" >&2
      exit 1
      ;;
    esac
    echo ":: PASS: Pathfinder installer environment reachable"

deploy-pathfinder-esp mode="installer":
    #!/usr/bin/env bash
    set -euo pipefail
    for marker in /tmp/pathfinder-esp-preflight.ok /tmp/pathfinder-esp-backup.ok; do
      test -f "$marker" || { echo ":: BLOCKED: missing $marker" >&2; exit 1; }
      age=$(( $(date +%s) - $(stat -c %Y "$marker") ))
      test "$age" -le 86400 || { echo ":: BLOCKED: stale $marker" >&2; exit 1; }
    done
    case "{{mode}}" in
      installer)
        just pathfinder-installer-preflight
        target_args=(nixos@{{ip_pathfinder}})
        ;;
      live)
        just pathfinder-esp-preflight
        # Keep --force-kexec away from argv tail: nixos-anywhere's parser does
        # two shifts for this valueless flag and exits 1 when it is last.
        target_args=(--force-kexec --target-host erik@{{ip_pathfinder}} --ssh-port 2222)
        ;;
      *) echo ":: mode must be installer or live" >&2; exit 1;;
    esac
    just dry pathfinder
    supplied_key="${PATHFINDER_LUKS_PASSWORD_FILE:-}"
    if [ -n "$supplied_key" ]; then
      test -f "$supplied_key" || { echo ":: missing PATHFINDER_LUKS_PASSWORD_FILE" >&2; exit 1; }
      mode=$(stat -c %a "$supplied_key")
      test "$mode" = 600 || { echo ":: passphrase file mode must be 600, got $mode" >&2; exit 1; }
      key=$(mktemp)
      chmod 600 "$key"
      cp "$supplied_key" "$key"
      echo ":: protected LUKS passphrase file accepted"
    else
      read -rsp "New Pathfinder LUKS passphrase: " LUKS_PASS; echo
      read -rsp "Confirm Pathfinder LUKS passphrase: " LUKS_CONFIRM; echo
      test "$LUKS_PASS" = "$LUKS_CONFIRM" || { echo ":: passphrases differ" >&2; exit 1; }
      key=$(mktemp)
      chmod 600 "$key"
      printf %s "$LUKS_PASS" > "$key"
      unset LUKS_PASS LUKS_CONFIRM
    fi
    extra=$(mktemp -d)
    trap 'rm -f "$key"; rm -rf "$extra"' EXIT
    mkdir -p "$extra/var/lib/sops-staging"
    cp ~/.config/sops/age/keys.txt "$extra/var/lib/sops-staging/age-keys.txt"
    chmod 600 "$extra/var/lib/sops-staging/age-keys.txt"
    echo ":: sops bootstrap key staged"
    echo ":: starting nixos-anywhere ({{mode}} mode)"
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#pathfinder \
      --extra-files "$extra" \
      --disk-encryption-keys /tmp/luks-password.txt "$key" \
      --debug \
      --show-trace \
      "${target_args[@]}"
    if [ -n "$supplied_key" ]; then rm -f "$supplied_key"; fi

# Approved destructive Endeavour install from NixOS installer media. Guards the
# exact replacement disk and reads its LUKS passphrase from a protected file.
deploy-endeavour:
    #!/usr/bin/env bash
    set -euo pipefail
    target=nixos@192.168.10.99
    disk=/dev/nvme0n1
    key=/tmp/endeavour-luks-password
    info=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$target" \
      'printf "root=%s\n" "$(findmnt -nro SOURCE /)"; lsblk -dn -o PATH,MODEL,SERIAL,SIZE /dev/nvme0n1')
    printf '%s\n' "$info"
    root=$(printf '%s\n' "$info" | sed -n 's/^root=//p')
    case "$root" in tmpfs|/dev/loop*|/dev/sr*|/dev/ram*) ;; \
      *) echo ":: BLOCKED: target is not booted from installer media" >&2; exit 1;; \
    esac
    disk_info=$(printf '%s\n' "$info" | tail -n 1)
    printf '%s\n' "$disk_info" | grep -Fq "$disk"
    printf '%s\n' "$disk_info" | grep -Fq "ADATA SX8200PNP"
    printf '%s\n' "$disk_info" | grep -Fq "2Q012L1K6JPH"
    test -f "$key" || { echo ":: BLOCKED: missing $key" >&2; exit 1; }
    test "$(stat -c %a "$key")" = 600 || { echo ":: passphrase file mode must be 600" >&2; exit 1; }
    test "$(stat -c %U "$key")" = erik || { echo ":: passphrase file owner must be erik" >&2; exit 1; }
    extra=$(mktemp -d)
    trap 'rm -rf "$extra"' EXIT
    mkdir -p "$extra/var/lib/sops-staging"
    install -m 600 ~/.config/sops/age/keys.txt "$extra/var/lib/sops-staging/age-keys.txt"
    just dry endeavour
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#endeavour \
      --extra-files "$extra" \
      --disk-encryption-keys /tmp/luks-password.txt "$key" \
      --debug \
      --show-trace \
      "$target"
    rm -f "$key"

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
    if [[ "{{user}}:{{port}}" == "root:22" ]]; then IP="{{ip_voyager}}"; else IP="{{tailscale_voyager}}"; fi
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

# Prove Voyager's OCI serial-console recovery path before a tailnet-only switch.
# Prints the current generation as the exact rollback target; executes no switch.
voyager-rollback-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! generation="$(
      timeout 15 ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=6 erik@{{tailscale_voyager}} bash -s <<'REMOTE'
    set -euo pipefail
    die() { echo "BLOCKED: $*" >&2; exit 2; }
    test "$(hostname)" = voyager || die "wrong host"
    test -c /dev/ttyS0 || die "serial console device missing"
    systemctl is-active --quiet serial-getty@ttyS0.service || die "serial getty inactive"
    who | awk '$1 == "erik" && $2 == "ttyS0" { found=1 } END { exit !found }' || die "no authenticated erik ttyS0 session"
    sudo -n true || die "passwordless sudo unavailable"
    status="$(passwd -S erik)"
    [[ "$status" == "erik P"* ]] || die "erik password login unavailable"
    link="$(readlink /nix/var/nix/profiles/system)"
    link="${link##*/}"
    [[ "$link" =~ ^system-([1-9][0-9]*)-link$ ]] || die "current system generation is invalid"
    generation="${BASH_REMATCH[1]}"
    sudo -n test -x "/nix/var/nix/profiles/system-$generation-link/bin/switch-to-configuration" || die "rollback generation is unavailable"
    test "$(readlink -f /run/current-system)" = "$(readlink -f "/nix/var/nix/profiles/system-$generation-link")" || die "system profile is not the running generation"
    printf '%s\n' "$generation"
    REMOTE
    )"; then
      echo "BLOCKED: Voyager console recovery preflight failed" >&2
      exit 2
    fi
    [[ "$generation" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCKED: invalid Voyager generation" >&2; exit 2; }
    echo ":: Open the authenticated OCI serial/web console and log in as erik before deployment."
    echo "rollback_generation=$generation"
    echo "sudo /run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --switch-generation $generation && sudo /nix/var/nix/profiles/system-$generation-link/bin/switch-to-configuration switch"
    echo "test \"\$(readlink -f /run/current-system)\" = \"\$(readlink -f /nix/var/nix/profiles/system-$generation-link)\""
    echo "sudo systemctl is-active sshd tailscaled"
    echo ":: After tailnet returns, run from the Servarr checkout: (cd machines && just check-stack voyager offsite)"
    echo ":: Confirm every required container is running/healthy; status output is not a fail-closed gate."

# Reconcile Voyager's locked live account to the already-declared Sops hash.
# Prints no hash or password; console login still requires a witnessed test.
recover-voyager-console-login:
    #!/usr/bin/env bash
    set -euo pipefail
    hash="$(sops decrypt --extract '["hashed_password"]' secrets/sops/secrets.yaml)"
    [[ "$hash" =~ ^\$y\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+$ ]] || {
      unset hash
      echo "BLOCKED: declarative login hash is not supported yescrypt" >&2
      exit 2
    }
    if ! printf 'erik:%s\n' "$hash" | timeout 20 ssh -p 2222 \
      -o BatchMode=yes -o ConnectTimeout=6 erik@{{tailscale_voyager}} '
        set -euo pipefail
        die() { echo "BLOCKED: $*" >&2; exit 2; }
        test "$(hostname)" = voyager || die "wrong host"
        sudo -n true || die "passwordless sudo unavailable"
        sudo -n chpasswd -e
        account_status="$(passwd -S erik)"
        [[ "$account_status" == "erik P"* ]] || die "erik password login unavailable: $account_status"
        echo "voyager_console_login=password-backed"
      '
    then
      unset hash
      exit 2
    fi
    unset hash
    echo ":: Open the OCI serial/web console and witness an erik password login."
    echo ":: Then run: just voyager-rollback-preflight"

# telstar (public projects host, Oracle A1 aarch64, 12 GB). Build on Orion
# (aarch64 via binfmt), activate on the target. First run after `just
# deploy-telstar` the base is erik@2222 already (nixos-anywhere set it). Stages
# the sops age key so sops-nix can decrypt secrets.
switch-telstar user="erik" port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(jq -r '.hosts.telstar.tailscaleIp // .hosts.telstar.ip' fleet.json)"
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
# age key. Roles (fleet-dns, dead-mans-switch, vault-witness) are
# opt-in — enable per the vanguard proposal after provisioning.
switch-vanguard user="erik" port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{user}}:{{port}}" == "root:22" ]]; then IP="{{ip_vanguard}}"; else IP="{{tailscale_vanguard}}"; fi
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

# Force the offsite outage alert once, then restore the healthy state.
test-vanguard-dead-mans-switch:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{tailscale_vanguard}} 'set -euo pipefail
      sudo systemctl stop dead-mans-switch.timer
      cleanup() { sudo systemctl start dead-mans-switch.timer; }
      trap cleanup EXIT
      sudo dead-mans-switch-probe
      sudo grep -qx 0 /var/lib/dead-mans-switch/failures
      output=$(for _ in {1..6}; do sudo dead-mans-switch-probe http://127.0.0.1:9; done 2>&1)
      printf "%s\n" "$output"
      grep -Fq "notification delivered" <<<"$output"
      sudo grep -qx 6 /var/lib/dead-mans-switch/failures
      sudo dead-mans-switch-probe
      sudo grep -qx 0 /var/lib/dead-mans-switch/failures
      cleanup
      trap - EXIT'

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
    BUILDERS="$(just _builders {{target}})"; \
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-substitutes --sudo --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true \
        --max-jobs 0

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
deploy-rs target:
    BUILDERS="$(just _builders {{target}})"; \
    nix run .#deploy-rs -- --skip-checks .#{{target}} \
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
    nix run .#deploy-rs -- --skip-checks --boot --fast-connection true .#{{target}} \
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

diagnose-pathfinder-bootstrap:
    ssh -p 2222 erik@$(jq -r '.hosts.pathfinder.tailscaleIp // .hosts.pathfinder.ip' fleet.json) "sudo systemctl status sops-first-boot home-manager-erik tailscaled-autoconnect --no-pager -l; echo ':: btrfs scrub'; sudo systemctl status btrfs-scrub--.timer btrfs-scrub--.service --no-pager -l || true; sudo systemctl cat btrfs-scrub--.timer; sudo journalctl -u btrfs-scrub--.timer -u btrfs-scrub--.service -b --no-pager -n 40; echo ':: account'; sudo passwd -S erik; echo ':: home path'; namei -l /home/erik/Documents/erik; echo ':: home-manager log'; sudo journalctl -u home-manager-erik -b --no-pager -n 80; echo ':: staging'; sudo find /var/lib/sops-staging -maxdepth 1 -type f -printf '%f %m %u:%g\n'; echo ':: age destination'; find ~/.config/sops/age -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null || true"

recover-pathfinder-scrub:
    ssh -p 2222 erik@$(jq -r '.hosts.pathfinder.tailscaleIp // .hosts.pathfinder.ip' fleet.json) "sudo systemctl reset-failed btrfs-scrub--.timer; sudo systemctl start btrfs-scrub--.timer; systemctl is-active btrfs-scrub--.timer"

diagnose-orion-bootstrap:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl status sops-first-boot home-manager-erik tailscaled-autoconnect --no-pager -l; echo ':: account'; sudo passwd -S erik; echo ':: home top-level'; find /home/erik -mindepth 1 -maxdepth 1 -printf '%f %y %u:%g\n' | sort; echo ':: ssh ownership'; namei -l /home/erik/.ssh/config; ls -la /home/erik/.ssh; echo ':: sops first-boot log'; sudo journalctl -u sops-first-boot -b --no-pager -n 100; echo ':: home-manager log'; sudo journalctl -u home-manager-erik -b --no-pager -n 100; echo ':: tailscale log'; sudo journalctl -u tailscaled-autoconnect -b --no-pager -n 100; echo ':: staging'; sudo find /var/lib/sops-staging -maxdepth 1 -type f -printf '%f %m %u:%g\n'; echo ':: age destination'; find ~/.config/sops/age -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null || true"

recover-orion-bootstrap:
    ssh -p 2222 erik@{{ip_orion}} "chmod u+w ~/.ssh/config; sudo systemctl reset-failed home-manager-erik tailscaled-autoconnect sops-first-boot; sudo systemctl start home-manager-erik; sudo systemctl start tailscaled-autoconnect; sudo systemctl reset-failed sops-first-boot"

recover-orion-nfs:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl reset-failed mnt-nfs-fast.mount mnt-nfs-bulk.mount; sudo systemctl restart mnt-nfs-fast.automount mnt-nfs-bulk.automount; timeout 15 ls -d /mnt/nfs/fast /mnt/nfs/bulk >/dev/null"

diagnose-orion-nfs:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl status mnt-nfs-fast.mount mnt-nfs-bulk.mount mnt-nfs-fast.automount mnt-nfs-bulk.automount --no-pager -l; sudo journalctl -b -u mnt-nfs-fast.mount -u mnt-nfs-bulk.mount --no-pager -n 100; echo ':: tailscale peers'; tailscale status; echo ':: tailscale dns'; tailscale dns status; echo ':: resolve kepler'; getent ahosts kepler || true; resolvectl query kepler || true; echo ':: nfs filesystems'; grep nfs /proc/filesystems || true; echo ':: modules'; lsmod | grep -E '(^nfs|sunrpc|lockd)' || true"

diagnose-gateway-reachability target:
    #!/usr/bin/env bash
    set -euo pipefail
    addr="$(jq -r --arg host "{{target}}" '.hosts[$host].tailscaleIp // empty' fleet.json)"
    [ -n "$addr" ] || addr="$(getent ahostsv4 "{{target}}" | awk 'NR == 1 {print $1}')"
    check() {
      cat <<'REMOTE'
      export PATH=/run/current-system/sw/bin
      gw=192.168.10.1
      echo ":: policy route"
      ip route get "$gw"
      ip rule
      ip route show table 52 2>/dev/null || true
      echo ":: Tailscale routing prefs"
      tailscale version | head -1
      tailscale debug prefs | grep -E '"RouteAll"|"AdvertiseTags"|"AdvertiseRoutes"'
      probe=1.1.1.1
      echo ":: routed TCP/443"
      timeout 2 bash -c "exec 3<>/dev/tcp/$probe/443" && echo "reachable" || echo "unreachable"
    REMOTE
    }
    if [ "{{target}}" = gemini ]; then
      check | ssh -p 2222 erik@{{ip_orion}} 'sudo systemd-run --machine=gemini --pipe --wait /run/current-system/sw/bin/bash -s'
    else
      check | ssh -p 2222 erik@"$addr" 'bash -s'
    fi

recover-orion-tailscale-routes:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      sudo tailscale set --accept-routes=false
      gw=192.168.10.1
      for _ in $(seq 1 10); do
        route="$(ip route get "$gw")"
        [[ "$route" == *"dev enp4s0"* ]] && break
        sleep 1
      done
      [[ "$route" == *"dev enp4s0"* ]] || {
        echo "gateway still routed through Tailscale: $route" >&2
        exit 1
      }
      probe=1.1.1.1
      timeout 2 bash -c "exec 3<>/dev/tcp/$probe/443"
      echo "gateway_route=physical routed_tcp_443=reachable"
    REMOTE

diagnose-orion-upgrade:
    #!/usr/bin/env bash
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      echo ":: routes"
      ip route
      gw="$(ip route show default | awk '/default/{print $3; exit}')"
      probe=1.1.1.1
      echo ":: routed TCP/443"
      timeout 2 bash -c "exec 3<>/dev/tcp/$probe/443" && echo "reachable" || echo "unreachable"
      echo ":: NetworkManager"
      systemctl status NetworkManager --no-pager -l || true
      nmcli general status
      nmcli device status
      echo ":: failed units"
      systemctl --failed --no-pager || true
      echo ":: upgrade"
      systemctl status nixos-upgrade.service --no-pager -l || true
      journalctl -u nixos-upgrade.service -n 120 --no-pager || true
      echo ":: generations"
      sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
      readlink -f /run/current-system
    REMOTE

diagnose-tailscale ip:
    ssh -p 2222 erik@{{ip}} "echo ':: peers'; tailscale status; echo ':: dns'; tailscale dns status"

verify-orion-esp:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} '
      set -euo pipefail
      echo ":: generation"; readlink -f /run/current-system
      echo ":: esp"; df -h /boot; findmnt -nro TARGET,SOURCE,FSTYPE,UUID /boot
      echo ":: preserved mounts"
      for mount in /projects /opt/models; do findmnt -nro TARGET,SOURCE,FSTYPE,UUID "$mount"; done
      test "$(findmnt -nro UUID /projects)" = d4511ef9-7f62-4f0f-86d2-ee015344c289
      test "$(findmnt -nro UUID /opt/models)" = 88a7f0d3-2fa2-4354-a4cd-8cab451dce85
      echo ":: restored home"; sudo du -xsh /home/erik
      test -f /home/erik/Documents/erik/desktop-nixos/flake.nix
      test -f /home/erik/Documents/erik/ha-agent/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors
      echo ":: core services"
      systemctl is-active home-manager-erik syncthing apparmor nix-serve
      curl --fail --silent --show-error http://127.0.0.1:5000/nix-cache-info
      tailscale status --peers=false
      echo ":: failed units"
      failed=$(systemctl --failed --no-legend | awk 'NF')
      printf '%s' "$failed"
      test -z "$failed"
    '

diagnose-pathfinder-login:
    ssh -p 2222 erik@{{ip_pathfinder}} "echo ':: account'; sudo passwd -S erik; echo ':: sddm'; sudo systemctl status display-manager --no-pager -l; echo ':: authentication log'; sudo journalctl -b --no-pager -n 150 -u display-manager -t sddm-helper -t unix_chkpwd -t systemd-logind"

# Workstations remain user-owned tailnet nodes; the fleet OAuth secret is
# intentionally scoped to tag:server and cannot enroll Pathfinder after a wipe.
pathfinder-tailscale-login:
    ssh -t -p 2222 erik@{{ip_pathfinder}} "sudo tailscale up --hostname=pathfinder --accept-dns=true --accept-routes && sudo systemctl reset-failed tailscaled-autoconnect.service && sudo systemctl start tailscaled-autoconnect.service"

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

# P3 read-only gate before enabling Kepler CoreDNS. Kepler :53 must be free;
# the existing vanguard tailnet resolver must still answer over UDP and TCP.
p3-dns-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER=$(just _host-ip kepler)
    VANGUARD_TAIL=$(jq -r '.hosts.vanguard.tailscaleIp' fleet.json)
    listeners=$(ssh -p 2222 erik@"$KEPLER" \
      "sudo ss -H -lntu 'sport = :53' | grep -Ev '127\\.0\\.0\\.(53|54)(%lo)?:53|\\[::1\\]:53' || true")
    test -z "$listeners" || { echo "BLOCKED: Kepler non-loopback port 53 already in use" >&2; exit 1; }
    for transport in +notcp +tcp; do
      test "$(dig "$transport" +short +time=3 +tries=1 @"$VANGUARD_TAIL" grafana.homelab.pastelariadev.com A)" = "192.168.10.250"
      test -n "$(dig "$transport" +short +time=3 +tries=1 @"$VANGUARD_TAIL" example.com A)"
    done
    echo ":: P3 preflight OK — Kepler :53 free; vanguard UDP/TCP DNS healthy"

# P3 direct-secondary verification after a Kepler deployment. DHCP remains
# untouched until this gate also passes after reboot.
p3-dns-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    KEPLER=$(just _host-ip kepler)
    for transport in +notcp +tcp; do
      test "$(dig "$transport" +short +time=3 +tries=1 @"$KEPLER" grafana.homelab.pastelariadev.com A)" = "192.168.10.250"
      test -n "$(dig "$transport" +short +time=3 +tries=1 @"$KEPLER" example.com A)"
      dig "$transport" +time=3 +tries=1 @"$KEPLER" grafana.homelab.pastelariadev.com AAAA | grep -q 'status: NOERROR'
    done
    ssh -p 2222 erik@"$KEPLER" '
      set -euo pipefail
      test "$(systemctl is-active coredns.service)" = active
      ! sudo ss -H -lntu "sport = :53" | grep -Eq "(^|[[:space:]])(0\\.0\\.0\\.0|\\[::\\]):53"
      test "$(systemctl show coredns.service -P NRestarts)" = 0
    '
    echo ":: P3 direct secondary OK — Kepler UDP/TCP fleet/external DNS healthy"

# Read-only Kepler secondary-DNS failure detail.
diagnose-kepler-dns:
    ssh -p 2222 erik@{{ip_kepler}} 'sudo systemctl status coredns.service --no-pager -l; sudo systemctl show coredns.service -p ActiveState -p SubState -p Result -p NRestarts; sudo ss -H -lntup "sport = :53"; sudo journalctl -u coredns.service -b --no-pager -n 80'

# Recover the existing listener after DHCP has assigned Kepler's LAN address.
recover-kepler-dns:
    ssh -p 2222 erik@{{ip_kepler}} 'sudo systemctl restart coredns.service'
    just p3-dns-verify

# P3 generic non-overlay client proof. Creates a temporary macvlan/netns on the
# explicitly wired parent, acquires a real DHCP lease, verifies option 6 and
# both resolvers, then proves the parent network is byte-for-byte unchanged.
p3-generic-dhcp-client interface="enp0s13f0u1u3":
    #!/usr/bin/env bash
    set -euo pipefail
    command -v dig >/dev/null
    builders=$(just _builders endeavour)
    busybox=$(nix build --inputs-from . --no-link --print-out-paths nixpkgs#busybox \
      --builders "$builders" --builders-use-substitutes --max-jobs 0)
    callback=$(sudo mktemp /run/p3-udhcpc-capture.XXXXXX)
    cleanup() { sudo rm -f "$callback"; }
    trap cleanup EXIT INT TERM
    sudo install -o root -g root -m 0755 scripts/p3-udhcpc-capture.sh "$callback"
    sudo scripts/p3-generic-dhcp-client.sh "{{interface}}" "$busybox/bin/udhcpc" "$callback"

# Prepare the persistent, isolated DHCP client used by the separately approved
# P3 AdGuard outage drill. This mutates only a temporary local netns/macvlan.
p3-adguard-outage-prepare interface="enp0s13f0u1u3" namespace="p3-dhcp-outage":
    #!/usr/bin/env bash
    set -euo pipefail
    evidence_dir=.gsd/evidence/p3-dns
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tooling_tmp= callback= tmp=
    cleanup() {
      test -z "$callback" || sudo rm -f "$callback"
      test -z "$tooling_tmp" || rm -f "$tooling_tmp"
      test -z "$tmp" || rm -f "$tmp"
    }
    trap cleanup EXIT INT TERM
    builders=$(just _builders endeavour)
    busybox=$(nix build --inputs-from . --no-link --print-out-paths nixpkgs#busybox \
      --builders "$builders" --builders-use-substitutes --max-jobs 0)
    ndisc6=$(nix build --inputs-from . --no-link --print-out-paths nixpkgs#ndisc6 \
      --builders "$builders" --builders-use-substitutes --max-jobs 0)
    tooling_tmp=$(mktemp "$evidence_dir/.tooling.XXXXXX")
    jq -cnS --arg rdisc6 "$ndisc6/bin/rdisc6" '{rdisc6:$rdisc6,version:1}' >"$tooling_tmp"
    mv "$tooling_tmp" "$evidence_dir/tooling.json"
    tooling_tmp=
    callback=$(sudo mktemp /run/p3-outage-udhcpc.XXXXXX)
    sudo install -o root -g root -m 0755 scripts/p3-udhcpc-capture.sh "$callback"
    tmp=$(mktemp "$evidence_dir/.client.XXXXXX")
    sudo scripts/p3-adguard-outage-client.sh prepare "{{namespace}}" "{{interface}}" \
      "$busybox/bin/udhcpc" "$callback" "$ndisc6/bin/rdisc6" >"$tmp"
    jq -e '.status == "prepared" and .version == 1' "$tmp" >/dev/null
    mv "$tmp" "$evidence_dir/client.json"
    tmp=
    echo ":: P3 outage client prepared — $evidence_dir/client.json"

# Capture the exact generic-client and Discovery container identities by LAN IP.
p3-adguard-outage-observe bound_ms="10000":
    #!/usr/bin/env bash
    set -euo pipefail
    evidence_dir=.gsd/evidence/p3-dns
    client="$evidence_dir/client.json"
    test -f "$client"
    namespace=$(jq -r .namespace "$client")
    interface=$(jq -r .interface "$client")
    discovery=$(just _host-ip discovery)
    known_hosts="$evidence_dir/known_hosts"
    known_tmp=$(mktemp "$evidence_dir/.known-hosts.XXXXXX")
    tmp=$(mktemp "$evidence_dir/.observation.XXXXXX")
    cleanup() { rm -f "$known_tmp" "$tmp"; }
    trap cleanup EXIT INT TERM
    ssh-keygen -F "[$discovery]:2222" -f "$HOME/.ssh/known_hosts" \
      | sed '/^#/d' >"$known_tmp"
    test -s "$known_tmp"
    chmod 0400 "$known_tmp"
    mv -f "$known_tmp" "$known_hosts"
    rdisc6=$(jq -r .rdisc6 "$evidence_dir/tooling.json")
    scripts/p3-adguard-outage-observe.sh "$namespace" "$interface" "$discovery" \
      "{{bound_ms}}" "$known_hosts" "$rdisc6" \
      scripts/p3-adguard-outage-client.sh scripts/p3-udhcpc-capture.sh >"$tmp"
    jq -e '.version == 3' "$tmp" >/dev/null
    mv "$tmp" "$evidence_dir/observation.json"
    trap - EXIT INT TERM
    echo ":: P3 outage observation captured — $evidence_dir/observation.json"

# Produce the deterministic value-free approval manifest. Read-only.
p3-adguard-outage-plan: p3-adguard-outage-observe
    #!/usr/bin/env bash
    set -euo pipefail
    evidence_dir=.gsd/evidence/p3-dns
    tmp=$(mktemp "$evidence_dir/.manifest.XXXXXX")
    trap 'rm -f "$tmp"' EXIT INT TERM
    rdisc6=$(jq -r .rdisc6 "$evidence_dir/tooling.json")
    scripts/p3-adguard-outage-drill.sh plan "$evidence_dir/observation.json" \
      "$evidence_dir/known_hosts" "$rdisc6" scripts/p3-adguard-outage-client.sh \
      scripts/p3-adguard-outage-observe.sh scripts/p3-udhcpc-capture.sh \
      modules/hosts/discovery/_stateful-adguard-inventory.py >"$tmp"
    jq -e '.manifest_sha256 | test("^[0-9a-f]{64}$")' "$tmp" >/dev/null
    mv "$tmp" "$evidence_dir/manifest.json"
    trap - EXIT INT TERM
    jq . "$evidence_dir/manifest.json"

# Execute only the exact approved manifest; restoration is an unconditional trap.
p3-adguard-outage-execute authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    evidence_dir=.gsd/evidence/p3-dns
    observation="$evidence_dir/observation.json"
    manifest="$evidence_dir/manifest.json"
    test -f "$observation" && test -f "$manifest"
    expected=$(jq -r .manifest_sha256 "$manifest")
    test "{{authorization}}" = "$expected" || { echo ":: BLOCKED: authorization differs" >&2; exit 1; }
    rdisc6=$(jq -r .rdisc6 "$evidence_dir/tooling.json")
    run_dir="$evidence_dir/runs/$(date -u +%Y%m%dT%H%M%SZ)-${expected:0:12}"
    mkdir -p "$evidence_dir/runs"
    set +e
    scripts/p3-adguard-outage-drill.sh execute "$observation" \
      "$evidence_dir/known_hosts" "$rdisc6" scripts/p3-adguard-outage-client.sh \
      scripts/p3-adguard-outage-observe.sh scripts/p3-udhcpc-capture.sh \
      modules/hosts/discovery/_stateful-adguard-inventory.py \
      "$run_dir" "{{authorization}}"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      jq -e '.status == "passed"' "$run_dir/result.json" >/dev/null
      jq . "$run_dir/result.json"
    else
      test -f "$run_dir/failure.json" && jq . "$run_dir/failure.json" || true
      echo ":: BLOCKED: retained outage journal at $run_dir" >&2
      exit "$rc"
    fi

# Offline reconstruction of the exact observation approved by a passed P3 run.
# Preserves the current input and recovered output as immutable 0400 artifacts.
p3-adguard-observation-recover run_dir preserved recovered:
    #!/usr/bin/env bash
    set -euo pipefail
    evidence_dir=.gsd/evidence/p3-dns
    python3 modules/hosts/discovery/_p3-observation-recover.py \
      "$evidence_dir/observation.json" "$evidence_dir/manifest.json" \
      "{{run_dir}}/result.json" "{{run_dir}}/journal.jsonl" \
      "{{preserved}}" "{{recovered}}" \
      "{{run_dir}}/core-worker-01.rows" "{{run_dir}}/core-worker-02.rows" \
      "{{run_dir}}/core-worker-03.rows" "{{run_dir}}/core-worker-04.rows" \
      "{{run_dir}}/diagnostic-worker-01.rows" "{{run_dir}}/diagnostic-worker-02.rows" \
      "{{run_dir}}/diagnostic-terminal-01.json" "{{run_dir}}/diagnostic-terminal-02.json"

# Remove only the local ephemeral outage client after a successful drill.
p3-adguard-outage-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail
    client=.gsd/evidence/p3-dns/client.json
    test -f "$client"
    namespace=$(jq -r .namespace "$client")
    sudo scripts/p3-adguard-outage-client.sh cleanup "$namespace"
    echo ":: P3 outage client removed; retained value-free evidence"

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
# → rename context to 'homelab' → ~/.kube/config. Run after a fresh laptop
# or a cluster reform. cp-1 (clusterInit server, 10.250.0.11) is on the private
# subnet, reached by agent-forward (kepler sshd disallows TCP forwarding).
kubeconfig:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    tmp=$(mktemp ~/.kube/config.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ssh -A -o StrictHostKeyChecking=accept-new -p 2222 erik@{{ip_kepler}} \
        'ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 "cat /etc/rancher/k3s/k3s.yaml"' \
        | sed 's#https://127.0.0.1:6443#https://k8s.pastelariadev.com:6443#' \
        | sed 's/: default$/: homelab/' \
        > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" ~/.kube/config
    trap - EXIT
    echo ":: kubeconfig → context $(kubectl config current-context)"
    kubectl get nodes

# LAN-direct kubeconfig → apiserver VIP 192.168.10.245 (cert SAN covers it),
# bypassing discovery's stream-proxy. Use on the kepler LAN or when discovery is
# down (grill §5 — admin access must not depend on a second host). Separate file;
# use via `KUBECONFIG=~/.kube/homelab-lan.yaml kubectl …`.
kubeconfig-lan:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    tmp=$(mktemp ~/.kube/homelab-lan.yaml.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ssh -A -o StrictHostKeyChecking=accept-new -p 2222 erik@{{ip_kepler}} \
        'ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 "cat /etc/rancher/k3s/k3s.yaml"' \
        | sed 's#https://127.0.0.1:6443#https://192.168.10.245:6443#' \
        | sed 's/: default$/: homelab-lan/' \
        > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" ~/.kube/homelab-lan.yaml
    trap - EXIT
    echo ":: LAN kubeconfig → ~/.kube/homelab-lan.yaml (context homelab-lan)"
    KUBECONFIG=~/.kube/homelab-lan.yaml kubectl get nodes

# Merge Gemini's single-node work cluster into ~/.kube/config without replacing
# the main homelab context or reusing k3s's default cluster/user names.
kubeconfig-pastelariadev:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ~/.kube
    current=~/.kube/config
    cluster=$(mktemp ~/.kube/pastelariadev.XXXXXX)
    base=$(mktemp ~/.kube/config-base.XXXXXX)
    merged=$(mktemp ~/.kube/config.XXXXXX)
    trap 'rm -f "$cluster" "$base" "$merged"' EXIT
    ssh gemini 'sudo -n cat /etc/rancher/k3s/k3s.yaml' \
        | sed 's#https://127.0.0.1:6443#https://gemini:6443#' \
        | sed 's/: default$/: pastelariadev-gemini/' \
        > "$cluster"
    chmod 600 "$cluster"
    KUBECONFIG="$cluster" kubectl config rename-context pastelariadev-gemini pastelariadev >/dev/null
    if [ -s "$current" ]; then
      active=$(KUBECONFIG="$current" kubectl config current-context 2>/dev/null || true)
      cp "$current" "$base"
      KUBECONFIG="$base" kubectl config delete-context pastelariadev >/dev/null 2>&1 || true
      KUBECONFIG="$base" kubectl config delete-cluster pastelariadev-gemini >/dev/null 2>&1 || true
      KUBECONFIG="$base" kubectl config delete-user pastelariadev-gemini >/dev/null 2>&1 || true
      KUBECONFIG="$base:$cluster" kubectl config view --raw --flatten > "$merged"
      if [ -n "$active" ]; then
        KUBECONFIG="$merged" kubectl config use-context "$active" >/dev/null
      fi
    else
      KUBECONFIG="$cluster" kubectl config view --raw --flatten > "$merged"
    fi
    chmod 600 "$merged"
    mv "$merged" "$current"
    trap - EXIT
    kubectl --context pastelariadev get nodes

# Read-only post-deploy proof through Gemini's existing Tailscale SSH path.
diagnose-pastelariadev:
    ssh gemini "sudo -n systemctl is-active k3s && sudo -n k3s kubectl get nodes -o wide && sudo -n ss -ltnp 'sport = :6443' || { sudo -n systemctl status k3s --no-pager -l; sudo -n journalctl -u k3s -b --no-pager -n 80; exit 1; }"

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
    target={{ quote(target) }}
    branch={{ quote(branch) }}
    [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "BLOCKED: invalid branch" >&2; exit 2; }
    git check-ref-format --branch "$branch" >/dev/null || { echo "BLOCKED: invalid branch" >&2; exit 2; }
    IP="$(jq -er --arg h "$target" '.hosts[$h].tailscaleIp // .hosts[$h].ip' fleet.json)"
    echo ":: Pointing $target servarr clone at origin/$branch and pulling..."
    ssh -p 2222 erik@"$IP" bash -s -- "$branch" <<'REMOTE'
    set -euo pipefail
    branch="$1"
    repo=/home/erik/servarr
    test ! -e "$repo/.deploy-commit" || { echo 'BLOCKED: exact Servarr revision pin exists' >&2; exit 2; }
    printf '%s\n' "$branch" > "$repo/.deploy-branch"
    REMOTE
    # daemon-reload picks up a freshly-deployed unit; restart (not start) is
    # required because servarr-pull is RemainAfterExit — `start` no-ops once it
    # has run, so the reset --hard would never re-fire.
    ssh -p 2222 erik@"$IP" 'uid=$(id -u); sudo systemctl start user-runtime-dir@$uid.service user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; systemctl --user daemon-reload && systemctl --user restart servarr-pull.service'
    ssh -p 2222 erik@"$IP" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status servarr-pull.service --no-pager -n15'
    echo ":: $target now on origin/$branch. Recreate changed stacks: just kick-stack $target <stack>"

# Pin one host to an exact Servarr commit already published on origin/main.
pin-servarr target commit:
    #!/usr/bin/env bash
    set -euo pipefail
    target={{ quote(target) }}
    commit={{ quote(commit) }}
    [[ "$target" =~ ^[a-z0-9-]+$ ]] || { echo "BLOCKED: invalid host" >&2; exit 2; }
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "BLOCKED: commit must be a full SHA-1" >&2; exit 2; }
    IP="$(jq -er --arg h "$target" '.hosts[$h].tailscaleIp // .hosts[$h].ip' fleet.json)"
    ssh -p 2222 erik@"$IP" bash -s -- "$commit" "$target" <<'REMOTE'
    set -euo pipefail
    commit="$1"
    target="$2"
    repo=/home/erik/servarr
    helper=$(readlink -f "$(command -v servarr-exact-revision)")
    case "$helper" in
      /nix/store/*/bin/servarr-exact-revision) ;;
      *) echo "BLOCKED: declarative servarr-exact-revision helper unavailable" >&2; exit 2 ;;
    esac
    "$helper" --help 2>&1 | grep -q pin-v2 || { echo "BLOCKED: deployed helper lacks pin-v2" >&2; exit 2; }
    flock -x /run/lock/servarr-repository.lock git -C "$repo" fetch --prune origin refs/heads/main:refs/remotes/origin/main
    "$helper" pin-v2 "$commit" "$target"
    uid=$(id -u)
    sudo -n /run/current-system/sw/bin/systemctl start "user-runtime-dir@$uid.service" "user@$uid.service"
    export XDG_RUNTIME_DIR="/run/user/$uid"
    systemctl --user daemon-reload
    systemctl --user restart servarr-pull.service
    systemctl --user status servarr-pull.service --no-pager -n15
    REMOTE

# Value-free exact-pin and runtime fingerprint for one Servarr rollout gate.
servarr-rollout-status target commit="":
    #!/usr/bin/env bash
    set -euo pipefail
    target={{ quote(target) }}
    commit={{ quote(commit) }}
    [[ "$target" =~ ^[a-z0-9-]+$ ]] || { echo "BLOCKED: invalid host" >&2; exit 2; }
    [[ -z "$commit" || "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "BLOCKED: commit must be a full SHA-1" >&2; exit 2; }
    IP="$(jq -er --arg h "$target" '.hosts[$h].tailscaleIp // .hosts[$h].ip' fleet.json)"
    ssh -p 2222 erik@"$IP" bash -s -- "$target" "$commit" <<'REMOTE'
    set -euo pipefail
    target="$1"
    expected="${2-}"
    repo=/home/erik/servarr
    die() { echo "BLOCKED: $*" >&2; exit 1; }
    helper="$(command -v servarr-exact-revision || true)"
    [[ -n "$helper" ]] || die "declarative exact-revision helper missing"
    helper="$(readlink -f "$helper")"
    case "$helper" in
      /nix/store/*/bin/servarr-exact-revision) ;;
      *) die "exact-revision helper is not declarative" ;;
    esac
    "$helper" --help 2>&1 | grep -q pin-v2 || die "deployed helper lacks pin-v2"
    head="$(git -C "$repo" rev-parse HEAD)"
    tree="$(git -C "$repo" show -s --format=%T HEAD)"
    pin_state=absent
    if [[ -e "$repo/.deploy-commit" ]]; then
      jq -e --arg machine "$target" '
        (keys | sort) == ["pin", "pin_sha256"] and
        (.pin | keys | sort) == ["commit", "machine", "tree", "version"] and
        .pin.version == 2 and .pin.machine == $machine and
        (.pin.commit | test("^[0-9a-f]{40}$")) and
        (.pin.tree | test("^[0-9a-f]{40}$")) and
        (.pin_sha256 | test("^[0-9a-f]{64}$"))
      ' "$repo/.deploy-commit" >/dev/null || die "malformed v2 pin"
      pin_sha="$(jq -jcS .pin "$repo/.deploy-commit" | sha256sum | cut -d' ' -f1)"
      [[ "$pin_sha" == "$(jq -r .pin_sha256 "$repo/.deploy-commit")" ]] || die "pin hash mismatch"
      [[ "$head" == "$(jq -r .pin.commit "$repo/.deploy-commit")" ]] || die "pin HEAD mismatch"
      [[ "$tree" == "$(jq -r .pin.tree "$repo/.deploy-commit")" ]] || die "pin tree mismatch"
      [[ -z "$expected" || "$head" == "$expected" ]] || die "unexpected exact pin"
      pin_state=v2
    else
      [[ -z "$expected" ]] || die "expected exact pin missing"
    fi
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    systemctl --user is-active servarr-pull.service >/dev/null || die "servarr-pull inactive"
    case "$target" in
      kepler) stacks=(infra buzz monitoring sync security whisper-gpu qwen4b-gpu retrieval) ;;
      orion) stacks=(shared monitoring ai-models sync) ;;
      voyager) stacks=(offsite) ;;
      *) die "host outside exact-pin rollout" ;;
    esac
    runtime="$(mktemp)"
    trap 'rm -f "$runtime"' EXIT
    container_count=0
    for stack in "${stacks[@]}"; do
      unit="podman-compose-$stack.service"
      systemctl --user is-enabled "$unit" >/dev/null || die "rollout unit disabled: $unit"
      systemctl --user is-active "$unit" >/dev/null || die "rollout unit inactive: $unit"
      mapfile -t ids < <(docker ps -aq \
        --filter "label=com.docker.compose.project=$stack" | sort)
      ((${#ids[@]} > 0)) || die "rollout stack has no containers: $stack"
      for id in "${ids[@]}"; do
        record="$(docker inspect -- "$id" | jq -cer '
          .[0] | {
            name: (.Name | ltrimstr("/")),
            state: (.State.Status + "/" + (.State.Health.Status // "none") + "/" + (.State.ExitCode | tostring)),
            fingerprint: [.Id, .Name, .Config.Labels["com.docker.compose.project"], .State.StartedAt]
          }
        ')"
        container_key="$(jq -r '.name + "/" + .state' <<<"$record")"
        case "$container_key" in
          */running/healthy/0|*/running/none/0|buzz-minio-init/exited/none/0|restic-rest-init/exited/none/0) ;;
          *) die "rollout container unhealthy" ;;
        esac
        jq -r '.fingerprint | @tsv' <<<"$record" >>"$runtime"
        ((container_count += 1))
      done
    done
    docker network inspect homelab-net >/dev/null || die "homelab-net missing"
    runtime_sha256="$(sort "$runtime" | sha256sum | cut -d' ' -f1)"
    printf 'target=%s pin=%s head=%s tree=%s units=%s containers=%s runtime_sha256=%s\n' \
      "$target" "$pin_state" "$head" "$tree" "${#stacks[@]}" "$container_count" "$runtime_sha256"
    REMOTE

# Repair only the Git checkout surface; leave untracked container runtime state alone.
repair-servarr-checkout target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'sudo -n bash -s' <<'REMOTE'
    set -euo pipefail
    repo=/home/erik/servarr
    test -d "$repo/.git"
    while IFS= read -r -d '' relative; do
      path="$repo/$relative"
      [[ -e "$path" || -L "$path" ]] && chown --no-dereference erik:users "$path"
      parent=$(dirname "$path")
      while test "$parent" != "$repo"; do
        chown --no-dereference erik:users "$parent"
        parent=$(dirname "$parent")
      done
    done < <(git -c safe.directory="$repo" -C "$repo" ls-files -z)
    chown -R erik:users "$repo/.git"
    echo "servarr_checkout=ownership_repaired"
    REMOTE

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

# Delegate Harbor robot provisioning to Servarr; token stays in the pipe.
provision-airflow-harbor-pull-robot:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} \
      'cd /home/erik/servarr && just provision-airflow-harbor-pull-robot'
    unset token

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

# Diagnose the per-user manager required by servarr-pull and compose units.
diagnose-servarr-user target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'sudo systemctl status systemd-logind.service user-runtime-dir@$(id -u).service user@$(id -u).service --no-pager -n20 || true; sudo journalctl -u systemd-logind.service -u user-runtime-dir@$(id -u).service -u user@$(id -u).service --no-pager -n30'

# Recover a user manager after logind loses its PID1 transport across reboot.
repair-servarr-user target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'uid=$(id -u); sudo systemctl restart systemd-logind.service; sudo systemctl restart user-runtime-dir@$uid.service; sudo systemctl start user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; state=$(systemctl --user is-system-running 2>/dev/null || true); printf "user-manager=%s\n" "$state"; case "$state" in starting|running|degraded) ;; *) exit 1;; esac'

# Run the sister repo's database backup on a deployed servarr host and prove
# the LiteLLM dump is non-empty and gzip-valid before a control-plane cutoff.
backup-servarr-db target:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      cd /home/erik/servarr/machines/{{target}}
      backup="backups/postgres/$(date +%Y-%m-%d_%H%M%S)"
      mkdir -p "$backup"
      user=$(sed -n "s/^POSTGRES_USER=//p" .env | tail -1)
      test -n "$user"
      docker exec postgres pg_dump -U "$user" litellm | gzip > "$backup/litellm.sql.gz"
      latest=$(find backups/postgres -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" | sort -nr | head -1 | cut -d" " -f2-)
      test -n "$latest"
      test -s "$latest/litellm.sql.gz"
      gzip -t "$latest/litellm.sql.gz"
      printf ":: verified LiteLLM DB backup: %s/litellm.sql.gz\n" "$latest"
    '

# Seed Kepler's compose-restic repositories and textfile gauges with real
# successful backups. Safe to rerun: restic deduplicates, gauges update only
# after each backup succeeds, and no credential values leave the containers.
seed-kepler-backup-metrics:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" 'bash -se' <<'REMOTE'
      set -euo pipefail
      podman exec postgres sh -ceu \
        'pg_dumpall -U "$POSTGRES_USER" > /backup/postgres.sql.tmp && mv /backup/postgres.sql.tmp /backup/postgres.sql'
      podman exec restic sh -ceu '
        if ! restic snapshots 2>/tmp/restic-error; then
          grep -q "repository does not exist" /tmp/restic-error || {
            cat /tmp/restic-error >&2
            exit 1
          }
          restic init
        fi
        restic backup /postgres/postgres.sql --tag postgres
        printf "restic_kepler_postgres_last_success_seconds %s\n" "$(date +%s)" > /metrics/restic_kepler_postgres.prom.tmp
        mv /metrics/restic_kepler_postgres.prom.tmp /metrics/restic_kepler_postgres.prom
        restic backup /config --tag configs
        printf "restic_kepler_configs_last_success_seconds %s\n" "$(date +%s)" > /metrics/restic_kepler_configs.prom.tmp
        mv /metrics/restic_kepler_configs.prom.tmp /metrics/restic_kepler_configs.prom
      '
      podman exec restic-offsite sh -ceu '
        if ! restic snapshots 2>/tmp/restic-error; then
          grep -q "repository does not exist" /tmp/restic-error || {
            cat /tmp/restic-error >&2
            exit 1
          }
          restic init
        fi
        restic backup /config --tag configs
        printf "restic_kepler_offsite_last_success_seconds %s\n" "$(date +%s)" > /metrics/restic_kepler_offsite.prom.tmp
        mv /metrics/restic_kepler_offsite.prom.tmp /metrics/restic_kepler_offsite.prom
      '
      test "$(find /var/lib/node-exporter-textfile -maxdepth 1 -name 'restic_kepler_*.prom' -type f | wc -l)" -eq 3
      echo ":: Kepler backup seeds and three success gauges verified"
    REMOTE

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
        --no-perms --no-owner --no-group --no-times \
        --exclude '.git' --exclude '__pycache__' --exclude '.DS_Store' \
        -e "ssh -p 2222" \
        "$SRC/" \
        "erik@$IP:/home/erik/hermes-skills/"

# Grafana alert inventory belongs to the GitOps repository with its runtime.
grafana-alert-status:
    #!/usr/bin/env bash
    echo "Moved to homelab-gitops: just grafana-alert-status" >&2
    exit 2

# Read recent systemd status and journal for the failed-unit alert allowlist.
grafana-alert-diagnostics:
    #!/usr/bin/env bash
    set -euo pipefail
    diagnose() {
      local host=$1 unit=$2
      echo ":: $host — $unit"
      if [ "$(hostname)" = "$host" ]; then
        systemctl status "$unit" --no-pager -l || true
        journalctl -u "$unit" -n 80 --no-pager || true
      else
        local ip
        ip="$(jq -r --arg host "$host" '.hosts[$host].tailscaleIp // empty' fleet.json)"
        [ -n "$ip" ] || ip="$(just _host-ip "$host")"
        ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 \
          -o ServerAliveInterval=3 -o ServerAliveCountMax=1 "erik@$ip" \
          "systemctl status '$unit' --no-pager -l || true; journalctl -u '$unit' -n 80 --no-pager || true" \
          || true
      fi
    }
    diagnose endeavour ampagent-watchdog.service
    diagnose endeavour nixos-upgrade.service
    diagnose kepler nixos-upgrade.service
    diagnose orion nix-cache-builder.service
    diagnose orion nixos-upgrade.service
    diagnose discovery telstar-capture.service
    diagnose discovery homelab-iac-drift.service

# Correlate Kepler's exporter, SSH, and recent kernel faults without mutation.
diagnose-kepler-kernel:
    #!/usr/bin/env bash
    set -euo pipefail
    metrics=$(curl --fail --silent --show-error --max-time 8 --get \
      https://prometheus.homelab.pastelariadev.com/api/v1/query \
      --data-urlencode 'query=up{instance="kepler",job="integrations/unix"}')
    printf 'metrics_up=%s\n' "$(jq -r '.data.result[0].value[1] // "missing"' <<<"$metrics")"

    ip=$(jq -r '.hosts.kepler.tailscaleIp // empty' fleet.json)
    [ -n "$ip" ] || ip=$(just _host-ip kepler)
    if boot_start=$(timeout 12 ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=5 \
      -o ServerAliveInterval=3 -o ServerAliveCountMax=1 "erik@$ip" \
      'date --date="$(uptime -s)" +%s%N'); then
      echo ssh_reachable=1
    else
      echo ssh_reachable=0
    fi

    logs=$(curl --fail --silent --show-error --max-time 8 --get \
      http://discovery:3100/loki/api/v1/query_range \
      --data-urlencode 'query={host="kepler"} |~ "BUG: unable to handle page fault|reboot is needed"' \
      --data-urlencode "start=$boot_start" \
      --data-urlencode 'limit=100' \
      --data-urlencode 'direction=backward')
    jq -r '.data.result[]?.values[]?[1]' <<<"$logs"
    if jq -e '[.data.result[]?.values[]?[1] | select(contains("reboot is needed"))] | length > 0' \
      >/dev/null <<<"$logs"; then
      echo reboot_required=1
      exit 2
    fi
    echo reboot_required=0

# Identify the process killed by the kernel OOM detector on Discovery.
grafana-alert-oom-diagnostics:
    ip="$(jq -r '.hosts.discovery.tailscaleIp // empty' fleet.json)"; \
    [ -n "$ip" ] || ip="$(just _host-ip discovery)"; \
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" \
      "journalctl -k --since '-20 minutes' --no-pager | grep -Ei 'oom|out of memory|killed process' || true"

# Clear or retry only the units covered by grafana-alert-diagnostics.
grafana-alert-retry target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      endeavour) host=endeavour; unit=ampagent-watchdog.service; action=start ;;
      endeavour-upgrade) host=endeavour; unit=nixos-upgrade.service; action=reset ;;
      kepler-upgrade) host=kepler; unit=nixos-upgrade.service; action=reset ;;
      orion) host=orion; unit=nixos-upgrade.service; action=reset ;;
      discovery-telstar) host=discovery; unit=telstar-capture.service; action=start-no-block ;;
      discovery-drift) host=discovery; unit=homelab-iac-drift.service; action=start ;;
      *) echo "target must be endeavour, endeavour-upgrade, kepler-upgrade, orion, discovery-telstar, or discovery-drift" >&2; exit 2 ;;
    esac
    command="sudo systemctl reset-failed '$unit'"
    [ "$action" = start ] && command="$command && sudo systemctl start '$unit'"
    [ "$action" = start-no-block ] && command="$command && sudo systemctl start --no-block '$unit'"
    if [ "$(hostname)" = "$host" ]; then
      bash -c "$command"
    else
      ip="$(jq -r --arg host "$host" '.hosts[$host].tailscaleIp // empty' fleet.json)"
      [ -n "$ip" ] || ip="$(just _host-ip "$host")"
      ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" "$command"
    fi

# One-shot, no-apply proof that the deployed pinned IaC source and an exact Git
# checkout produce identical action metadata. Raw plans stay in private /run
# scratch and are deleted; only the normalized evidence envelope is retained.
p2-iac-plan-equivalence:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    REV="$(jq -r '.nodes["homelab-iac"].locked.rev' flake.lock)"
    [[ "$REV" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid homelab-iac lock revision" >&2; exit 2; }
    ip="$(jq -r '.hosts.discovery.tailscaleIp // empty' fleet.json)"
    [ -n "$ip" ] || ip="$(just _host-ip discovery)"
    evidence=.gsd/evidence/p2-iac-plan-equivalence.json
    evidence_dir="${evidence%/*}"
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tmp="$(mktemp "$evidence_dir/.plan-equivalence.XXXXXX")"
    trap 'rm -f -- "$tmp"' EXIT
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" \
      sudo bash -s -- "$REV" >"$tmp" <<'REMOTE'
    set -euo pipefail
    umask 077
    REV=$1
    [[ "$REV" =~ ^[0-9a-f]{40}$ ]] || exit 2
    [ "$(hostname)" = discovery ] || { echo "wrong host" >&2; exit 1; }
    [ "$(systemctl show -p User --value homelab-iac-drift.service)" = erik ] || exit 1

    timer=homelab-iac-drift.timer
    service=homelab-iac-drift.service
    timer_was_active=0
    mask_applied=0
    systemctl is-active --quiet "$timer" && timer_was_active=1
    scratch="$(mktemp -d /run/homelab-iac-p2.XXXXXX)"
    chown erik:users "$scratch"
    chmod 700 "$scratch"
    cleanup() {
      rc=$?
      rm -rf -- "$scratch" || rc=1
      if [ "$mask_applied" -eq 1 ]; then
        systemctl unmask --runtime "$service" >/dev/null || rc=1
      fi
      if [ "$timer_was_active" -eq 1 ]; then
        systemctl start "$timer" || rc=1
      fi
      exit "$rc"
    }
    trap cleanup EXIT
    trap 'exit 130' HUP INT TERM

    systemctl stop "$timer"
    systemctl is-failed --quiet "$service" && { echo "drift canary failed; retry it first" >&2; exit 1; }
    exec_start="$(systemctl show -p ExecStart --value "$service" | sed -n 's/^{ path=\([^ ;]*\).*/\1/p')"
    [ -x "$exec_start" ] || { echo "invalid deployed drift command" >&2; exit 1; }
    unit_env="$(systemctl show -p Environment --value "$service")"
    for assignment in $unit_env; do
      assignment="${assignment#\"}"
      assignment="${assignment%\"}"
      case "$assignment" in
        PATH=*|TG_TF_PATH=*|SOPS_AGE_KEY_FILE=*|TF_PLUGIN_CACHE_DIR=*|OCI_SSH_PUBKEY_FILE=*|OCI_CONSOLE_PUBKEY_FILE=*)
          export "$assignment"
          ;;
      esac
    done
    [ -n "${PATH:-}" ] && [ -n "${TG_TF_PATH:-}" ] && [ -n "${TF_PLUGIN_CACHE_DIR:-}" ] && [ -n "${SOPS_AGE_KEY_FILE:-}" ] || exit 1
    export PATH="$PATH:/run/current-system/sw/bin"
    case "$(systemctl is-enabled "$service" 2>/dev/null || true)" in
      masked*) echo "drift service already masked" >&2; exit 1 ;;
    esac
    mask_applied=1
    systemctl mask --runtime "$service" >/dev/null
    service_state="$(systemctl show -p ActiveState --value "$service")"
    [ "$service_state" = inactive ] || { echo "drift service state is $service_state" >&2; exit 1; }
    if pgrep -u erik -f '(^|/)(terragrunt|tofu)( |$)' >/dev/null; then
      echo "another IaC process is active" >&2
      exit 1
    fi

    compare="$scratch/compare"
    shim_dir="$scratch/shim"
    mkdir "$shim_dir"
    cat >"$compare" <<'COMPARE'
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    export DISCORD_WEBHOOK_URL=""
    pinned=/var/lib/homelab-iac-drift/source
    scratch="${P2_SCRATCH:?}"
    REV="${P2_REV:?}"
    legacy="$scratch/legacy"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    git -c init.defaultBranch=main init --quiet "$legacy"
    git -C "$legacy" remote add origin https://github.com/ErikBPF/homelab-iac.git
    git -C "$legacy" fetch --quiet --depth=1 origin "$REV"
    git -C "$legacy" checkout --quiet --detach FETCH_HEAD
    [ "$(git -C "$legacy" rev-parse HEAD)" = "$REV" ]
    [ -z "$(git -C "$legacy" status --porcelain)" ]
    diff -qr --exclude=.git --exclude=.terragrunt-cache "$pinned" "$legacy" >/dev/null

    normalize() {
      local json_dir=$1 output=$2 units=$3
      find "$json_dir" -type f -name '*.json' -printf '%P\n' | LC_ALL=C sort >"$units"
      [ -s "$units" ] || { echo "no plan JSON produced" >&2; return 1; }
      : >"$output"
      while IFS= read -r unit; do
        jq -c --arg unit "$unit" '
          def resource($scope):
            .[]? | select(.change.actions != ["no-op"]) |
            {unit:$unit,scope:$scope,address,previous_address,mode,type,name,index,deposed,
             actions:.change.actions,action_reason};
          (.resource_changes | resource("resource_changes")),
          (.resource_drift | resource("resource_drift")),
          (.output_changes // {} | to_entries[] |
            select((.value.actions // ["no-op"]) != ["no-op"]) |
            {unit:$unit,scope:"output_changes",name:.key,actions:.value.actions})
        ' "$json_dir/$unit" >>"$output"
      done <"$units"
      LC_ALL=C sort -o "$output" "$output"
    }

    run_plan() {
      local label=$1 source=$2 raw="$scratch/results-$1"
      mkdir -p "$raw/plans" "$raw/json"
      set +e
      (cd "$source" && TG_OUT_DIR="$raw/plans" TG_JSON_OUT_DIR="$raw/json" \
        /run/current-system/sw/bin/bash bin/drift-check.sh >"$raw/run.log" 2>&1)
      local rc=$?
      set -e
      case "$rc" in 0|2) ;; *) echo "$label plan failed: $rc" >&2; return 1 ;; esac
      printf '%s' "$rc" >"$raw/exit"
      normalize "$raw/json" "$raw/normalized.jsonl" "$raw/units"
    }

    run_plan pinned "$pinned"
    run_plan legacy "$legacy"
    pinned_exit="$(cat "$scratch/results-pinned/exit")"
    legacy_exit="$(cat "$scratch/results-legacy/exit")"
    [ "$pinned_exit" = "$legacy_exit" ]
    cmp -s "$scratch/results-pinned/units" "$scratch/results-legacy/units"
    cmp -s "$scratch/results-pinned/normalized.jsonl" "$scratch/results-legacy/normalized.jsonl"
    tree="$(git -C "$legacy" rev-parse "$REV^{tree}")"
    units="$(wc -l <"$scratch/results-pinned/units")"
    actions="$(wc -l <"$scratch/results-pinned/normalized.jsonl")"
    normalized_sha256="$(sha256sum "$scratch/results-pinned/normalized.jsonl" | cut -d' ' -f1)"
    terragrunt_version="$(terragrunt --version | head -1)"
    tofu_version="$($TG_TF_PATH version -json | jq -r .terraform_version)"
    jq -nS \
      --arg revision "$REV" --arg tree "$tree" \
      --arg started_at "$started" --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg terragrunt_version "$terragrunt_version" --arg tofu_version "$tofu_version" \
      --arg normalized_sha256 "$normalized_sha256" \
      --argjson exit_code "$pinned_exit" --argjson units "$units" --argjson action_count "$actions" \
      --slurpfile normalized_actions "$scratch/results-pinned/normalized.jsonl" \
      '{schema:"homelab-iac-plan-equivalence-v1",revision:$revision,tree:$tree,
        started_at:$started_at,completed_at:$completed_at,terragrunt_version:$terragrunt_version,
        tofu_version:$tofu_version,pinned_exit:$exit_code,legacy_exit:$exit_code,units:$units,
        action_count:$action_count,normalized_sha256:$normalized_sha256,
        normalized_actions:$normalized_actions}'
    COMPARE
    chmod 700 "$compare"
    cat >"$shim_dir/bash" <<'SHIM'
    #!/bin/sh
    if [ "$#" -eq 1 ] && [ "$1" = bin/drift-check.sh ]; then
      exec "$P2_COMPARE"
    fi
    exec /run/current-system/sw/bin/bash "$@"
    SHIM
    chmod 700 "$shim_dir/bash"
    chown -R erik:users "$scratch"
    /run/wrappers/bin/sudo -u erik env -i \
      HOME=/home/erik USER=erik STATE_DIRECTORY=/var/lib/homelab-iac-drift \
      TG_TF_PATH="$TG_TF_PATH" TF_PLUGIN_CACHE_DIR="$TF_PLUGIN_CACHE_DIR" SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" \
      OCI_SSH_PUBKEY_FILE="${OCI_SSH_PUBKEY_FILE:-}" OCI_CONSOLE_PUBKEY_FILE="${OCI_CONSOLE_PUBKEY_FILE:-}" \
      P2_SCRATCH="$scratch" P2_REV="$REV" P2_COMPARE="$compare" \
      PATH="$shim_dir:$PATH" "$exec_start"
    REMOTE
    jq -e --arg rev "$REV" '
      .schema == "homelab-iac-plan-equivalence-v1" and
      .revision == $rev and
      .pinned_exit == .legacy_exit and (.pinned_exit == 0 or .pinned_exit == 2) and
      .units > 0 and .action_count == (.normalized_actions | length)
    ' "$tmp" >/dev/null
    mv "$tmp" "$evidence"
    trap - EXIT
    jq -r --arg evidence "$evidence" '":: P2 equivalence PASS revision=\(.revision) units=\(.units) actions=\(.action_count) sha256=\(.normalized_sha256) evidence=\($evidence)"' "$evidence"

# Pause the Discovery Telstar capacity retry while its remote state is repaired.
pause-discovery-telstar:
    ssh -p 2222 erik@{{ip_discovery}} 'sudo systemctl stop telstar-capture.service; sudo systemctl reset-failed telstar-capture.service'

# Recover one confirmed stale Telstar state lock, then resume capacity retries.
# Destructive: pass the exact lock UUID from the failed plan output.
recover-discovery-telstar-lock lock_id:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{lock_id}}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo "lock_id must be an exact UUID" >&2; exit 2; }
    just pause-discovery-telstar
    ssh -p 2222 erik@{{ip_discovery}} 'set -euo pipefail
      cd /var/lib/telstar-capture/source
      bash oracle/bin/telstar-lock-recover.sh "{{lock_id}}"
      sudo systemctl reset-failed telstar-capture.service
      sudo systemctl start telstar-capture.service'

# Compare encrypted Telstar state copies without printing state content.
discovery-telstar-state-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    inspect() {
      local host=$1 ip=$2 path=$3
      printf 'host=%s ' "$host"
      ssh -p 2222 erik@"$ip" "if test -f '$path'; then stat -c 'bytes=%s mtime=%y' '$path'; sha256sum '$path'; else echo state=missing; fi"
    }
    inspect discovery {{ip_discovery}} /home/erik/tofu-state-export/oracle/compute-telstar/terraform.tfstate
    inspect orion {{ip_orion}} /home/erik/tofu-state-backup/oracle/compute-telstar/terraform.tfstate
    inspect kepler {{ip_kepler}} /home/erik/tofu-state-backup/oracle/compute-telstar/terraform.tfstate

# After pulling, kick the compose stack on the remote host:
#   just kick-stack kepler ai-serving
kick-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    # restart (not start): the unit is RemainAfterExit, so `start` no-ops once
    # active and would not re-run `compose up -d --remove-orphans`.
    ssh -p 2222 erik@$IP 'uid=$(id -u); sudo systemctl start user-runtime-dir@$uid.service user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; systemctl --user restart podman-compose-{{stack}}.service'
    ssh -p 2222 erik@$IP 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status podman-compose-{{stack}}.service --no-pager -n10'

# Read-only failure detail for a compose unit.
diagnose-stack target stack:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip {{target}})"
    ssh -p 2222 erik@"$IP" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status podman-compose-{{stack}}.service --no-pager -n30 || true; journalctl --user -u podman-compose-{{stack}}.service --no-pager -n50'

# One-time cutover from the old manually started stateless BGE containers.
kepler-retire-legacy-retrieval:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip kepler)"
    ssh -p 2222 erik@"$IP" 'bash -se' <<'REMOTE'
      set -euo pipefail
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      digest=@sha256:aedf3b34836dc57289583142adcf2b93836cda0736ac8e6ce43691b9c2c67170
      legacy=ghcr.io/huggingface/text-embeddings-inference:86-1.9
      systemctl --user stop podman-compose-retrieval.service || true
      for name in bge-m3 bge-reranker-v2-m3; do
        mapfile -t ids < <(docker ps -aq --no-trunc --filter "name=^/${name}$")
        [[ ${#ids[@]} -le 1 ]]
        if [[ ${#ids[@]} -eq 1 ]]; then
          docker inspect -- "${ids[0]}" | jq -r --arg name "$name" '
            .[0] | "name=\(.Name) image=\(.Config.Image) project=\(.Config.Labels["com.docker.compose.project"] // "none")"
          '
          docker inspect -- "${ids[0]}" | jq -e --arg name "$name" --arg digest "$digest" --arg legacy "$legacy" '
            .[0]
            | select(.Name == $name or .Name == "/" + $name)
            | select(
                (.Config.Image | endswith($digest))
                or (
                  .Config.Image == $legacy
                  and .Config.Labels["com.docker.compose.project"] == "kepler"
                )
              )
          ' >/dev/null
          docker rm -f -- "${ids[0]}" >/dev/null
        fi
      done
      systemctl --user reset-failed podman-compose-retrieval.service
      systemctl --user restart podman-compose-retrieval.service
      systemctl --user status podman-compose-retrieval.service --no-pager -n15
    REMOTE

# Remove Orion's stateless legacy llama-chat, then use the canonical stack lifecycle.
orion-retire-legacy-llama:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip orion)"
    ssh -p 2222 erik@"$IP" 'bash -se' <<'REMOTE'
      set -euo pipefail
      test "$(hostname)" = orion
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
      mapfile -t ids < <(docker ps -aq --no-trunc \
        --filter label=com.docker.compose.project=homelab \
        --filter label=com.docker.compose.service=llama-chat)
      [[ "${#ids[@]}" -le 1 ]]
      if [[ "${#ids[@]}" -eq 1 ]]; then
        legacy_id="${ids[0]}"
        docker inspect -- "$legacy_id" | jq -e --arg id "$legacy_id" '
          .[0]
          | select(.Id == $id)
          | select(.Config.Labels["com.docker.compose.project.working_dir"] == "/home/erik/homelab")
          | select(.Config.Labels["com.docker.compose.project.config_files"] == "ai-models.yml")
        ' >/dev/null
        systemctl --user stop podman-compose-ai-models.service
        docker stop --time 30 -- "$legacy_id" >/dev/null
        docker rm -- "$legacy_id" >/dev/null
      fi
    REMOTE
    just kick-stack orion ai-models

# Live proof for Orion's Kubernetes-backed Wazuh canary.
verify-wazuh-agent-canary:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'set -euo pipefail
      systemctl is-active wazuh-agent-vault.service podman-wazuh-agent.service
      sudo podman inspect wazuh-agent | jq -e '\''.[0].State.Status == "running"'\'' >/dev/null'
    echo ":: Manager enrollment"
    kubectl --context homelab -n wazuh exec statefulset/wazuh-manager-master -c wazuh-manager -- \
      sh -c '/var/ossec/bin/agent_control -lc | grep -F orion-canary >/dev/null'
    echo ":: Attributed alert"
    kubectl --context homelab -n wazuh exec statefulset/wazuh-manager-worker -c wazuh-manager -- \
      sh -c 'tail -n 10000 /var/ossec/logs/alerts/alerts.json | grep -Eq '\''"name"[[:space:]]*:[[:space:]]*"orion-canary"'\'''
    echo ":: Orion Wazuh canary enrolled and attributed alerts present"

probe-wazuh-agent-canary:
    #!/usr/bin/env bash
    set -euo pipefail
    marker="wazuh-canary-$(date +%s)"
    printf 'Aug 26 01:00:00 orion sshd[4242]: Failed password for invalid user %s from 192.0.2.1 port 4242 ssh2\n' "$marker" |
      ssh -p 2222 erik@{{ip_orion}} "sudo podman exec -i wazuh-agent sh -c 'cat >> /var/ossec/logs/active-responses.log'"
    seen=false
    for _ in {1..30}; do
      if kubectl --context homelab -n wazuh exec statefulset/wazuh-manager-worker -c wazuh-manager -- \
        sh -c "tail -n 10000 /var/ossec/logs/alerts/alerts.json | grep -F '$marker' | grep -Eq '\"name\"[[:space:]]*:[[:space:]]*\"orion-canary\"'"; then
        seen=true
        break
      fi
      sleep 2
    done
    "$seen"
    just verify-wazuh-agent-canary

# Read-only filesystem allocation and largest top-level trees on Kepler.
diagnose-kepler-disk:
    ssh -p 2222 erik@{{ip_kepler}} 'df -h / /fast; sudo btrfs filesystem usage /; sudo btrfs device stats /; sudo btrfs scrub status /; sudo journalctl --no-pager _TRANSPORT=kernel | grep -Ei "BTRFS|Structure needs cleaning|I/O error|corrupt" || true; sudo zfs list -o name,mountpoint,used,available,recordsize; systemctl cat microvm@cp-1.service; pgrep -af "openwakeword|ha-train|huggingface|kaggle" || true; sudo du -x -d2 -B1 /nix /var /home 2>/dev/null | sort -nr | head -40; sudo du -x -d2 -B1 /home/erik/.local /home/erik/.cache /home/erik/openwakeword-training /home/erik/ha-train /home/erik/ha-hf /var/lib/microvms 2>/dev/null | sort -nr | head -40'

# Remove reproducible Hugging Face model caches only.
clean-kepler-model-cache:
    ssh -p 2222 erik@{{ip_kepler}} 'test "$(hostname)" = kepler; du -sh /home/erik/ha-hf /home/erik/hf-cache 2>/dev/null || true; rm -rf -- /home/erik/ha-hf /home/erik/hf-cache; df -h /'

# Quiesce k3s, create fast-pool datasets, and copy+verify state. Old Btrfs
# copies remain until finalize-kepler-fast-state passes its post-switch gates.
prepare-kepler-fast-state:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} 'bash -se' <<'REMOTE'
    set -euo pipefail
    test "$(hostname)" = kepler
    command -v rsync >/dev/null
    available=$(sudo zfs get -Hp -o value available fast-pool/data)
    test "$available" -gt 214748364800
    if pgrep -u erik -f 'python.*(openwakeword|ha-train)|kaggle' >/dev/null; then
      echo "active training process; refusing migration" >&2
      exit 1
    fi

    sudo systemctl stop microvm@w-2.service microvm@w-1.service
    sudo systemctl stop microvm@cp-3.service microvm@cp-2.service microvm@cp-1.service
    test "$(systemctl is-active microvm@cp-{1,2,3}.service microvm@w-{1,2}.service | grep -c '^inactive$')" -eq 5

    create_dataset() {
      local name=$1 mountpoint=$2 recordsize=$3
      if ! sudo zfs list -H "$name" >/dev/null 2>&1; then
        sudo zfs create -o mountpoint="$mountpoint" -o atime=off \
          -o compression=zstd -o recordsize="$recordsize" "$name"
      fi
    }
    create_dataset fast-pool/ai /fast/ai 1M
    create_dataset fast-pool/ai/cache /fast/ai/cache 1M
    create_dataset fast-pool/ai/training /fast/ai/training 1M
    create_dataset fast-pool/ai/environments /fast/ai/environments 128K
    create_dataset fast-pool/microvms /fast/microvms 64K
    sudo install -d -o erik -g users /fast/ai/cache /fast/ai/training /fast/ai/environments

    migrate_user_tree() {
      local source target old delta
      source=$1
      target=$2
      old="${source}.btrfs-migration-old"
      if [ -L "$source" ]; then
        test "$(readlink -f "$source")" = "$target"
        return
      fi
      test ! -e "$old"
      mkdir -p "$target"
      if [ -d "$source" ]; then
        rsync -aHAXS --numeric-ids "$source/" "$target/"
        delta=$(rsync -aHAXS --numeric-ids --checksum --dry-run --itemize-changes "$source/" "$target/")
        test -z "$delta"
        mv "$source" "$old"
      else
        mkdir -p "$old"
      fi
      ln -s "$target" "$source"
    }
    migrate_user_tree /home/erik/openwakeword-training /fast/ai/training/openwakeword
    migrate_user_tree /home/erik/ha-train /fast/ai/training/ha
    migrate_user_tree /home/erik/ha-uvenv /fast/ai/environments/ha-uvenv
    migrate_user_tree /home/erik/.cache /fast/ai/cache/user
    migrate_user_tree /home/erik/ha-hf /fast/ai/cache/huggingface
    migrate_user_tree /home/erik/hf-cache /fast/ai/cache/hf-cache

    sudo rsync -aHAXS --numeric-ids /var/lib/microvms/ /fast/microvms/
    delta=$(sudo rsync -aHAXS --numeric-ids --checksum --dry-run --itemize-changes \
      /var/lib/microvms/ /fast/microvms/)
    test -z "$delta"
    sudo zfs list -o name,mountpoint,used,available,recordsize \
      fast-pool/ai fast-pool/ai/cache fast-pool/ai/training \
      fast-pool/ai/environments fast-pool/microvms
    echo "prepare complete; old Btrfs copies retained"
    REMOTE

# Remove only source copies after the switched units and cluster prove they use
# /fast. The user explicitly approved this destructive migration.
finalize-kepler-fast-state:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} 'bash -se' <<'REMOTE'
    set -euo pipefail
    test "$(hostname)" = kepler
    state_dir=$(systemctl show microvm@cp-1.service -p WorkingDirectory --value | sed 's,/cp-1$,,' )
    test "$state_dir" = /fast/microvms
    systemctl cat microvm@cp-1.service | grep -q 'RequiresMountsFor=/fast/microvms'
    test "$(systemctl is-active microvm@cp-{1,2,3}.service microvm@w-{1,2}.service | grep -c '^active$')" -eq 5
    for pair in \
      /home/erik/openwakeword-training:/fast/ai/training/openwakeword \
      /home/erik/ha-train:/fast/ai/training/ha \
      /home/erik/ha-uvenv:/fast/ai/environments/ha-uvenv \
      /home/erik/.cache:/fast/ai/cache/user \
      /home/erik/ha-hf:/fast/ai/cache/huggingface \
      /home/erik/hf-cache:/fast/ai/cache/hf-cache
    do
      source=${pair%%:*}
      target=${pair#*:}
      test -L "$source"
      test "$(readlink -f "$source")" = "$target"
    done
    sudo rm -rf --one-file-system -- /var/lib/microvms
    rm -rf -- \
      /home/erik/openwakeword-training.btrfs-migration-old \
      /home/erik/ha-train.btrfs-migration-old \
      /home/erik/ha-uvenv.btrfs-migration-old \
      /home/erik/.cache.btrfs-migration-old \
      /home/erik/ha-hf.btrfs-migration-old \
      /home/erik/hf-cache.btrfs-migration-old
    df -h / /fast
    echo "finalize complete; old Btrfs copies removed"
    REMOTE

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
      test "$(sudo stat -c '"'"'%a %U %G'"'"' /run/vault-agent/tunneling.env)" = "440 root docker"
      sudo -u erik head -c0 /run/vault-agent/tunneling.env
      if sudo -u nobody head -c0 /run/vault-agent/tunneling.env 2>/dev/null; then
        echo "nobody unexpectedly read tunneling render" >&2
        exit 1
      fi
      sudo find /run/vault-agent/tunneling.env -mmin -15 -print -quit | grep -q .
      actual="$(sudo grep -v '^#' /run/vault-agent/tunneling.env | cut -d= -f1)"
      test "$actual" = CLOUDFLARE_TUNNEL_TOKEN
      echo "tunneling_render=ready mode=0440 owner=root group=docker fresh=true"
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

# Refresh the OpenBao snapshot across every declared tier, then prove restore.
backup-discovery-openbao-d4:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
      set -euo pipefail
      units=(
        restic-backups-vault.service
        restic-backups-vault-offsite.service
        restic-backups-vault-rest.service
        restic-backups-vault-b2.service
      )
      for unit in "${units[@]}"; do
        sudo systemctl start "$unit"
        snapshot=$(sudo journalctl -u "$unit" -n 200 --no-pager -o cat |
          sed -n \
            -e 's/.*snapshot \([0-9a-f]\{8,\}\) saved.*/\1/p' \
            -e 's/.*"snapshot_id":"\([0-9a-f]\{8,\}\)".*/\1/p' |
          tail -1)
        test -n "$snapshot"
        printf 'unit=%s snapshot=%s\n' "$unit" "$snapshot"
      done
      sudo sha256sum /var/lib/vault-snapshots/openbao.snap
      sudo systemctl start openbao-restore-drill.service
      test "$(systemctl show openbao-restore-drill.service --property=Result --value)" = success
    REMOTE
    echo ":: PASS: fresh OpenBao snapshot copied to every tier and restored"

openbao-restore-drill:
    IP="$(just _host-ip discovery)"; ssh -p 2222 erik@"$IP" 'sudo systemctl start openbao-restore-drill.service && { sudo systemctl status openbao-restore-drill.service --no-pager || true; }'

openbao-restore-drill-diagnose:
    IP="$(just _host-ip discovery)"; ssh -p 2222 erik@"$IP" 'sudo systemctl status openbao-restore-drill.service --no-pager -l || true; sudo journalctl -u openbao-restore-drill.service --no-pager -n 100'


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

# Seed the Kindle dashboard runtime credentials from the encrypted Servarr
# source into OpenBao. Secret values travel only over stdin and never print.
seed-kindle-dash-vault:
    #!/usr/bin/env bash
    set -euo pipefail
    servarr_repo="$(readlink -f references/repos/servarr)"
    secret_json="$(mktemp)"
    payload_file="$(mktemp)"
    trap 'rm -f "$secret_json" "$payload_file"' EXIT
    chmod 600 "$secret_json" "$payload_file"
    sops --decrypt --input-type dotenv --output-type json \
      "$servarr_repo/machines/discovery/.env.sops" > "$secret_json"
    jq -e '{
      data: {
        KINDLE_DASH_CLAUDE_REFRESH_TOKEN: .KINDLE_DASH_CLAUDE_REFRESH_TOKEN,
        KINDLE_DASH_CODEX_REFRESH_TOKEN: .KINDLE_DASH_CODEX_REFRESH_TOKEN,
        KINDLE_DASH_HA_TOKEN: .KINDLE_DASH_HA_TOKEN,
        KINDLE_DASH_OPENCODE_AUTH_COOKIE: .KINDLE_DASH_OPENCODE_AUTH_COOKIE
      }
    }
    | select(
        (.data | keys | length) == 4
        and all(.data[]; type == "string" and length > 0)
      )' "$secret_json" > "$payload_file"
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
        --data-binary @"$body" \
        http://127.0.0.1:8200/v1/secret/data/home/kindle-dash >/dev/null
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
      echo "kindle_dash_vault=seeded keys=4"
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

# Permanently remove the seven disposable AI containers, their seven exact
# images, and /fast/ai-models. The helper re-inventories and fails closed.
kepler-retire-ai-serving-user-approved:
    ssh -p 2222 erik@{{ip_kepler}} 'tool=$(command -v kepler-collision-recovery-inventory); interpreter=$(head -n1 "$tool"); interpreter=${interpreter#\#!}; exec "$interpreter" - --execute-user-approved' < modules/hosts/kepler/_retire_ai_serving.py

# Activate the generation staged by `just switch-kepler`, then wait for SSH.
reboot-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=10 \
        erik@{{ip_kepler}} sudo systemd-run --collect --on-active=2s systemctl reboot
    echo ":: waiting for kepler to stop..."
    for _ in $(seq 1 30); do
        if ! ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@{{ip_kepler}} true 2>/dev/null; then
            break
        fi
        sleep 1
    done
    echo ":: waiting for kepler to return..."
    for _ in $(seq 1 150); do
        if ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@{{ip_kepler}} true 2>/dev/null; then
            echo ":: kepler reachable"
            exit 0
        fi
        sleep 2
    done
    echo ":: kepler did not return within 300s" >&2
    exit 1

# Re-prove peer-dependent Discovery units after a fleet reboot. The unrelated
# IaC drift failure is left for its owning repo and only reset for this window.
recover-discovery-reboot-blockers:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
    set -euo pipefail
    for unit in mnt-nfs-fast.mount restic-backups-vault-offsite.service restic-check-voyager.service; do
      sudo systemctl reset-failed "$unit"
      sudo systemctl start "$unit" || {
        sudo systemctl status "$unit" --no-pager -l || true
        sudo journalctl -u "$unit" -n 80 --no-pager || true
        exit 1
      }
    done
    sudo systemctl reset-failed homelab-iac-drift.service
    test -z "$(systemctl --failed --no-legend)"
    REMOTE

# Reboot Discovery and prove the host transitioned down then up. The separate
# `just discovery-swag-transition-amendment-execute ...` repeats the exact P1
# SWAG gates after this returns.
reboot-discovery:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    set +e
    ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 erik@"$IP" sudo systemctl reboot
    reboot_status=$?
    set -e
    if (( reboot_status != 0 && reboot_status != 255 )); then
        echo ":: discovery reboot dispatch failed with status $reboot_status" >&2
        exit 1
    fi
    echo ":: waiting for discovery to stop..."
    saw_down=0
    for _ in $(seq 1 30); do
        if ! ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@"$IP" true 2>/dev/null; then
            saw_down=1
            break
        fi
        sleep 1
    done
    if (( saw_down == 0 )); then
        echo ":: discovery never became unreachable after reboot dispatch" >&2
        exit 1
    fi
    echo ":: waiting for discovery to return..."
    deadline=$((SECONDS + 240))
    while (( SECONDS < deadline )); do
        if ssh -p 2222 -o BatchMode=yes -o ConnectionAttempts=1 -o ConnectTimeout=2 erik@"$IP" true 2>/dev/null; then
            echo ":: discovery reachable"
            just verify discovery "$IP" 2222 erik
            exit 0
        fi
        sleep 2
    done
    echo ":: discovery did not return within 240s" >&2
    exit 1

restart-k3s-worker target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      w-1|w-2|w-3) ;;
      *) echo "invalid worker: {{target}}" >&2; exit 2 ;;
    esac
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl restart microvm@{{target}}.service"
    kubectl --context homelab wait --for=condition=Ready node/{{target}} --timeout=5m

# Read-only proof for the k3s guest reconciler and embedded-etcd metrics.
verify-k3s-observability:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      for attempt in $(seq 1 60); do
        states=$(sudo systemctl is-active microvm@cp-1.service microvm@cp-2.service microvm@cp-3.service || true)
        if [ "$(printf '%s\n' "$states" | grep -c '^active$')" -eq 3 ]; then
          break
        fi
        if [ "$attempt" -eq 60 ]; then
          printf '%s\n' "$states" >&2
          exit 1
        fi
        sleep 5
      done
      for node in 11 12 13; do
        ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.$node \
          "systemctl is-active k3s.service k3s-manifest-reconcile.service"
        curl --fail --silent --show-error --max-time 5 http://10.250.0.$node:2381/metrics \
          | grep -c "^etcd_server_has_leader 1$" | grep -qx 1
      done
    '
    response=$(kubectl --context homelab -n monitoring exec \
      statefulset/prometheus-monitoring-kube-prometheus-prometheus -c prometheus -- \
      wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D%22etcd%22%7D')
    printf '%s\n' "$response" | jq -c '.data.result[]? | {instance: .metric.instance, value: .value[1]}'
    test "$(printf '%s\n' "$response" | jq '[.data.result[]? | select(.value[1] == "1")] | length')" -eq 3

# Grow existing k3s root images to the sizes declared in k3s-cluster.nix.
# Offline + grow-only: shrinking or an unexpected filesystem aborts.
resize-kepler-k3s-disks:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} 'sudo bash -s' <<'REMOTE'
      set -euo pipefail
      declare -A sizes=(
        [cp-1]=32768 [cp-2]=32768 [cp-3]=32768
        [w-1]=131072 [w-2]=131072
      )
      names=(cp-1 cp-2 cp-3 w-1 w-2)
      systemctl stop microvms.target "${names[@]/#/microvm@}"
      trap 'systemctl start microvms.target' EXIT
      for name in "${names[@]}"; do
        image="/fast/microvms/$name/root.img"
        test -f "$image"
        file -s "$image" | grep -q 'ext4 filesystem'
        current=$(stat -c %s "$image")
        wanted=$((sizes[$name] * 1024 * 1024))
        (( current > wanted )) && {
          echo "refusing to shrink $name: $current > $wanted" >&2
          exit 1
        }
        if (( current < wanted )); then
          truncate -s "$wanted" "$image"
        fi
        e2fsck -fp "$image" || [ "$?" -eq 1 ]
        resize2fs "$image"
      done
      trap - EXIT
      systemctl start microvms.target
    REMOTE

# Prove every compose host exports container identity through its native
# collector: cAdvisor on Docker, podman-exporter on rootless Podman.
verify-container-metrics:
    #!/usr/bin/env bash
    set -euo pipefail
    response=$(curl --fail --silent --show-error --get https://prometheus.homelab.pastelariadev.com/api/v1/query \
      --data-urlencode 'query=container_last_seen or podman_container_info')
    failed=0
    for host in discovery kepler orion; do
      raw_count=$(printf '%s\n' "$response" | jq --arg host "$host" '[.data.result[]? | select(.metric.host == $host)] | length')
      named_count=$(printf '%s\n' "$response" | jq --arg host "$host" '[.data.result[]? | select(.metric.host == $host and (.metric.name // "") != "")] | length')
      printf '%s raw_containers=%s named_containers=%s\n' "$host" "$raw_count" "$named_count"
      [ "$named_count" -gt 0 ] || failed=1
    done
    exit "$failed"

# Inspect the host collector when container metrics verification fails.
diagnose-container-metrics host:
    ssh -p 2222 erik@{{host}} \
      "systemctl show alloy docker --property=Id,ActiveState,SubState,Result,ActiveEnterTimestamp --no-pager; getent ahostsv4 prometheus.homelab.pastelariadev.com; curl -fsS http://127.0.0.1:12345/metrics | grep -E 'prometheus_remote_(storage|write)' || true; journalctl -b -u alloy --no-pager -n 300 | grep -Ei 'remote_write|prometheus|cadvisor|containerd|docker|factory' || true"

# Read-only proof that cp-1's timer last reconciled both bootstrap Secrets.
verify-k3s-bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 '\''
        set -euo pipefail
        systemctl is-active k3s-bootstrap-secrets.timer
        test "$(systemctl show k3s-bootstrap-secrets.service -p Result --value)" = success
        k3s kubectl -n argocd get secret homelab-gitops-repo -o name
        k3s kubectl -n external-secrets get secret vault-approle -o name
        k3s kubectl wait --for=condition=Ready clustersecretstore/vault-discovery --timeout=2m
      '\''
    '

# Read-only startup detail for k3s microVMs and their virtiofs helpers.
diagnose-k3s-guests:
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl list-jobs --no-pager; sudo systemctl status microvms.target k3s-bootstrap-materialize.service microvm@cp-{1,2,3}.service --no-pager -l; sudo journalctl -b -u k3s-bootstrap-materialize.service -u microvm@cp-1.service -u install-microvm-cp-1.service --no-pager -n 120; sudo find -L /run/secrets -maxdepth 2 -printf 'secret-path %P %y\n'; sudo find /run/k3s-bootstrap -maxdepth 1 -type f -printf 'host %f %s bytes\n'; ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 'find /run/k3s-bootstrap -maxdepth 1 -type f -printf \"guest %f %s bytes\\n\"; systemctl status k3s.service k3s-bootstrap-secrets.service k3s-bootstrap-secrets.timer --no-pager -l; journalctl -b -u k3s.service -u k3s-bootstrap-secrets.service --no-pager -n 120'"

# Retry the exact bootstrap dependency chain after a diagnosed boot failure.
recover-k3s-bootstrap-guest:
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl reset-failed k3s-bootstrap-materialize.service microvm@cp-1.service; sudo systemctl start k3s-bootstrap-materialize.service microvm@cp-1.service"

# Acceptance test: delete only the two bootstrap Secrets, run the reconciler,
# and prove both return. Values are never read or printed.
test-k3s-bootstrap-recovery:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_kepler}} '
      set -euo pipefail
      ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 '\''
        set -euo pipefail
        k3s kubectl -n argocd delete secret homelab-gitops-repo
        k3s kubectl -n external-secrets delete secret vault-approle
        systemctl start k3s-bootstrap-secrets.service
        k3s kubectl -n argocd get secret homelab-gitops-repo -o name
        k3s kubectl -n external-secrets get secret vault-approle -o name
        k3s kubectl wait --for=condition=Ready clustersecretstore/vault-discovery --timeout=2m
      '\''
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

# List OpenBao audit devices and safe transport options only.
openbao-audit-status:
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
      curl --header @"$cfg" --silent --show-error --fail http://127.0.0.1:8200/v1/sys/audit |
        jq -c ".data | to_entries | map({path:.key,type:.value.type,options:(.value.options | {file_path,log_raw,hmac_accessor})})"
    '

# Rotate ESO's dedicated AppRole secret ID and capture both k3s bootstrap
# credentials directly into sops. Secret values never enter argv or stdout.
capture-k3s-bootstrap-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    secret_id=$(
      printf '%s\n' "$token" | ssh -p 2222 erik@{{ip_discovery}} '
        set -euo pipefail
        IFS= read -r token
        cfg=$(mktemp)
        trap "rm -f $cfg" EXIT
        printf "X-Vault-Token: %s\n" "$token" > "$cfg"
        unset token
        chmod 600 "$cfg"
        curl --header @"$cfg" --silent --show-error --fail --request POST \
          "http://127.0.0.1:8200/v1/auth/approle/role/eso/secret-id" \
          | jq -er .data.secret_id
      '
    )
    unset token
    printf '%s' "$secret_id" | jq -Rs . \
      | sops set --value-stdin secrets/sops/secrets.yaml '["k3s_bootstrap"]["vault_approle_secret_id"]'
    unset secret_id
    kubectl --context homelab -n argocd get secret homelab-gitops-repo \
      -o jsonpath='{.data.sshPrivateKey}' \
      | base64 --decode \
      | jq -Rs . \
      | sops set --value-stdin secrets/sops/secrets.yaml '["k3s_bootstrap"]["argocd_repo_ssh_key"]'
    echo ":: k3s bootstrap credentials encrypted in sops"

# Mint lane-scoped ESO AppRole credentials after homelab-iac has applied the
# policies/roles. Values travel only through stdin and encrypted Sops writes.
capture-k3s-vault-lane-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    for lane in platform homelab home-services; do
      credentials=$(
        printf '%s\n%s\n' "$token" "$lane" | ssh -p 2222 erik@{{ip_discovery}} '
          set -euo pipefail
          IFS= read -r token
          IFS= read -r lane
          case "$lane" in platform|homelab|home-services) ;; *) exit 2 ;; esac
          cfg=$(mktemp)
          trap "rm -f $cfg" EXIT
          printf "X-Vault-Token: %s\n" "$token" > "$cfg"
          unset token
          chmod 600 "$cfg"
          role_id=$(curl --header @"$cfg" --silent --show-error --fail \
            "http://127.0.0.1:8200/v1/auth/approle/role/eso-$lane/role-id" | jq -er .data.role_id)
          secret_id=$(curl --header @"$cfg" --silent --show-error --fail --request POST \
            "http://127.0.0.1:8200/v1/auth/approle/role/eso-$lane/secret-id" | jq -er .data.secret_id)
          jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" "\$ARGS.named"
        '
      )
      lane_key=${lane//-/_}
      role_path='["k3s_bootstrap"]["vault_approle_'"$lane_key"'_role_id"]'
      secret_path='["k3s_bootstrap"]["vault_approle_'"$lane_key"'_secret_id"]'
      jq -er .role_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml "$role_path"
      jq -er .secret_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml "$secret_path"
      unset credentials
    done
    unset token
    echo ":: lane AppRole credentials encrypted in sops"

# Rotate exact-path Harbor reader/publisher AppRole credentials into Sops.
capture-harbor-project-iam-approle-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    for capability in reader publisher; do
      role="svc-homelab-iac-openbao-harbor-project-iam-$capability"
      credentials=$(
        printf '%s\n%s\n' "$token" "$role" | ssh -p 2222 erik@{{ip_discovery}} '
          set -euo pipefail
          IFS= read -r token
          IFS= read -r role
          case "$role" in
            svc-homelab-iac-openbao-harbor-project-iam-reader|svc-homelab-iac-openbao-harbor-project-iam-publisher) ;;
            *) exit 2 ;;
          esac
          cfg=$(mktemp)
          accessor_file="${cfg}.accessors"
          trap "rm -f $cfg $accessor_file" EXIT
          printf "X-Vault-Token: %s\n" "$token" > "$cfg"
          unset token
          chmod 600 "$cfg"
          http_status=$(curl --header @"$cfg" --silent --show-error --request LIST \
            --output "$accessor_file" --write-out "%{http_code}" \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id")
          case "$http_status" in
            200) accessors=$(cat "$accessor_file") ;;
            404) accessors='{"data":{"keys":[]}}' ;;
            *) echo "SecretID accessor listing returned HTTP $http_status" >&2; exit 1 ;;
          esac
          while IFS= read -r accessor; do
            jq -cn --arg accessor "$accessor" "{secret_id_accessor: \$accessor}" | \
              curl --header @"$cfg" --silent --show-error --fail --request POST \
                --data @- \
                "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id-accessor/destroy" \
                >/dev/null
          done < <(jq -r ".data.keys[]?" <<<"$accessors")
          role_id=$(curl --header @"$cfg" --silent --show-error --fail \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/role-id" | jq -er .data.role_id)
          secret_id=$(curl --header @"$cfg" --silent --show-error --fail --request POST \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id" | jq -er .data.secret_id)
          jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" "\$ARGS.named"
        '
      )
      key_prefix="openbao_harbor_project_iam_$capability"
      jq -jer .role_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "[\"homelab_iac\"][\"${key_prefix}_role_id\"]"
      jq -jer .secret_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "[\"homelab_iac\"][\"${key_prefix}_secret_id\"]"
      unset credentials
    done
    unset token
    echo ":: Harbor project-IAM AppRole credentials rotated into sops"

# Rotate the fleet-reader publisher plus each projected host's exact-read
# AppRole directly into Sops. Harbor robot values remain OpenBao-only.
capture-harbor-fleet-reader-approle-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    token=$(sops --decrypt --extract '["vault_root_token"]' secrets/sops/secrets.yaml)
    for identity in publisher discovery endeavour kepler; do
      case "$identity" in
        publisher)
          role=svc-homelab-iac-openbao-harbor-fleet-readers-publisher
          key_prefix=openbao_harbor_fleet_readers_publisher
          key_scope='["homelab_iac"]'
          ;;
        discovery|endeavour|kepler)
          role="svc-desktop-nixos-$identity-harbor-reader"
          key_prefix="openbao_harbor_reader_${identity}"
          key_scope=
          ;;
        *) exit 2 ;;
      esac
      credentials=$(
        printf '%s\n%s\n' "$token" "$role" | ssh -p 2222 erik@{{ip_discovery}} '
          set -euo pipefail
          IFS= read -r token
          IFS= read -r role
          case "$role" in
            svc-homelab-iac-openbao-harbor-fleet-readers-publisher|svc-desktop-nixos-discovery-harbor-reader|svc-desktop-nixos-endeavour-harbor-reader|svc-desktop-nixos-kepler-harbor-reader) ;;
            *) exit 2 ;;
          esac
          cfg=$(mktemp)
          accessor_file="${cfg}.accessors"
          trap "rm -f $cfg $accessor_file" EXIT
          printf "X-Vault-Token: %s\n" "$token" > "$cfg"
          unset token
          chmod 600 "$cfg"
          http_status=$(curl --header @"$cfg" --silent --show-error --request LIST \
            --output "$accessor_file" --write-out "%{http_code}" \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id")
          case "$http_status" in
            200) accessors=$(cat "$accessor_file") ;;
            404) accessors='{"data":{"keys":[]}}' ;;
            *) echo "SecretID accessor listing returned HTTP $http_status" >&2; exit 1 ;;
          esac
          while IFS= read -r accessor; do
            jq -cn --arg accessor "$accessor" "{secret_id_accessor: \$accessor}" | \
              curl --header @"$cfg" --silent --show-error --fail --request POST \
                --data @- \
                "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id-accessor/destroy" \
                >/dev/null
          done < <(jq -r ".data.keys[]?" <<<"$accessors")
          role_id=$(curl --header @"$cfg" --silent --show-error --fail \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/role-id" | jq -er .data.role_id)
          secret_id=$(curl --header @"$cfg" --silent --show-error --fail --request POST \
            "http://127.0.0.1:8200/v1/auth/approle/role/$role/secret-id" | jq -er .data.secret_id)
          jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" "\$ARGS.named"
        '
      )
      jq -jer .role_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "${key_scope}[\"${key_prefix}_role_id\"]"
      jq -jer .secret_id <<<"$credentials" | jq -Rs . \
        | sops set --value-stdin secrets/sops/secrets.yaml \
          "${key_scope}[\"${key_prefix}_secret_id\"]"
      unset credentials
    done
    unset token
    echo ":: Harbor fleet-reader AppRole credentials rotated into sops"

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

# Probe only reviewed retirement paths. The helper emits metadata, never
# directory listings, contents, environment, or content-derived hashes.
kepler-recovery-retirement-paths:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    helper="modules/hosts/kepler/_collision_recovery_retirement_paths_remote.py"
    evidence_dir=".gsd/evidence/kepler-k1"
    out="$evidence_dir/retirement-paths.json"
    test -f "$helper"
    mkdir -p "$evidence_dir"
    chmod 700 "$evidence_dir"
    tmp="$(mktemp "$evidence_dir/.retirement-paths.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} \
      'tool=$(command -v kepler-collision-recovery-inventory); interpreter=$(head -n1 "$tool"); interpreter=${interpreter#\#!}; exec "$interpreter" -' \
      < "$helper" > "$tmp"
    python3 - "$tmp" <<'PY'
    import hashlib
    import json
    import pathlib
    import sys

    result = json.loads(pathlib.Path(sys.argv[1]).read_text())
    evidence = result.get("evidence")
    canonical = (json.dumps(evidence, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if (
        result.get("schema") != "kepler-retirement-path-evidence-envelope-v1"
        or result.get("status") != "verified"
        or not isinstance(evidence, list)
        or result.get("evidence_sha256") != hashlib.sha256(canonical).hexdigest()
    ):
        raise SystemExit("retirement path evidence envelope/hash validation failed")
    PY
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'retirement_paths=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["evidence_sha256"])' "$out")"

# Render only the separately-approved stop plan. This recipe never stops a service.
kepler-recovery-quiesce-plan inventory_sha256:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    evidence_dir=".gsd/evidence/kepler-k1"
    inventory="$evidence_dir/inventory.json"
    desired="$evidence_dir/desired.json"
    out="$evidence_dir/quiesce-manifest.json"
    python3 modules/hosts/kepler/_collision_recovery_desired.py \
      --servarr-root references/repos/servarr/machines/kepler > "$desired"
    python3 modules/hosts/kepler/_collision_recovery_quiesce.py \
      --inventory "$inventory" --desired "$desired" \
      --expected-inventory-sha256 "{{inventory_sha256}}" > "$out"
    chmod 600 "$desired" "$out"
    printf 'quiesce_manifest=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$out")"

# Produce restore-tested PostgreSQL evidence, bound to fresh inventory and ID.
kepler-recovery-postgres-evidence-run inventory_sha256 container_id mode="run-stopped":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    case "{{mode}}" in run|run-stopped) ;; *) echo "invalid evidence mode" >&2; exit 2 ;; esac
    python3 - "{{inventory_sha256}}" "{{container_id}}" <<'PY'
    import json, pathlib, sys
    inventory = json.loads(pathlib.Path(".gsd/evidence/kepler-k1/inventory.json").read_text())
    expected_sha, expected_id = sys.argv[1:]
    records = [item for item in inventory["inventory"]["containers"] if item.get("name") == "postgres"]
    if inventory.get("inventory_sha256") != expected_sha or len(records) != 1 or records[0].get("id") != expected_id:
        raise SystemExit("PostgreSQL inventory binding mismatch")
    PY
    out=".gsd/evidence/kepler-k1/database-evidence.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.database-evidence.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    submission="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job \
      submit postgres "{{mode}}" "{{inventory_sha256}}" "{{container_id}}")"
    request_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["request_sha256"])' "$submission")"
    [[ $request_sha =~ ^[0-9a-f]{64}$ ]] || { echo "invalid PostgreSQL evidence request" >&2; exit 2; }
    for _ in $(seq 1 180); do
      if ! status="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job status "$request_sha")"; then
        sleep 5
        continue
      fi
      state="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["state"])' "$status")"
      case "$state" in
        passed)
          ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job result "$request_sha" > "$tmp" && break
          ;;
        failed)
          reason="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("reason", "unspecified"))' "$status")"
          echo "PostgreSQL evidence job failed: $reason" >&2
          exit 2
          ;;
        pending|running) ;;
        *) echo "invalid PostgreSQL evidence job state" >&2; exit 2 ;;
      esac
      sleep 5
    done
    [[ -s $tmp ]] || { echo "PostgreSQL evidence job timed out; remote job was not stopped" >&2; exit 2; }
    python3 -m json.tool "$tmp" >/dev/null
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'database_evidence=%s\n' "$out"

# Produce restore-tested Redis evidence, bound to the fresh inventory and ID.
kepler-recovery-redis-evidence-run inventory_sha256 container_id mode="run-stopped":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    case "{{mode}}" in run|run-stopped) ;; *) echo "invalid evidence mode" >&2; exit 2 ;; esac
    python3 - "{{inventory_sha256}}" "{{container_id}}" <<'PY'
    import json, pathlib, sys
    inventory = json.loads(pathlib.Path(".gsd/evidence/kepler-k1/inventory.json").read_text())
    expected_sha, expected_id = sys.argv[1:]
    records = [item for item in inventory["inventory"]["containers"] if item.get("name") == "redis"]
    if inventory.get("inventory_sha256") != expected_sha or len(records) != 1 or records[0].get("id") != expected_id:
        raise SystemExit("Redis inventory binding mismatch")
    PY
    out=".gsd/evidence/kepler-k1/redis-evidence.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.redis-evidence.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    submission="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job \
      submit redis "{{mode}}" "{{inventory_sha256}}" "{{container_id}}")"
    request_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["request_sha256"])' "$submission")"
    [[ $request_sha =~ ^[0-9a-f]{64}$ ]] || { echo "invalid Redis evidence request" >&2; exit 2; }
    for _ in $(seq 1 180); do
      if ! status="$(ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job status "$request_sha")"; then
        sleep 5
        continue
      fi
      state="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["state"])' "$status")"
      case "$state" in
        passed)
          ssh -p 2222 erik@{{ip_kepler}} kepler-collision-evidence-job result "$request_sha" > "$tmp" && break
          ;;
        failed)
          reason="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("reason", "unspecified"))' "$status")"
          echo "Redis evidence job failed: $reason" >&2
          exit 2
          ;;
        pending|running) ;;
        *) echo "invalid Redis evidence job state" >&2; exit 2 ;;
      esac
      sleep 5
    done
    [[ -s $tmp ]] || { echo "Redis evidence job timed out; remote job was not stopped" >&2; exit 2; }
    python3 -m json.tool "$tmp" >/dev/null
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'redis_evidence=%s\n' "$out"

# Validate value-free retained PostgreSQL backup/restore evidence locally.
kepler-recovery-postgres-evidence-plan inventory_sha256 evidence=".gsd/evidence/kepler-k1/database-evidence.json":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    out=".gsd/evidence/kepler-k1/database-manifest.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.database-manifest.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/kepler/_collision_recovery_database_evidence.py \
      --inventory .gsd/evidence/kepler-k1/inventory.json \
      --evidence "{{evidence}}" \
      --expected-inventory-sha256 "{{inventory_sha256}}" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'database_manifest=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$out")"

# Render the exact Redis backup/restore plan; never executes its actions.
kepler-recovery-redis-backup-plan inventory_sha256 approval="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(
      --inventory .gsd/evidence/kepler-k1/inventory.json
      --expected-inventory-sha256 "{{inventory_sha256}}"
    )
    if [ -n "{{approval}}" ]; then args+=(--quiesce-approval "{{approval}}"); fi
    python3 modules/hosts/kepler/_collision_recovery_redis_backup.py "${args[@]}"

# Assemble value-free retirement evidence from authenticated live envelopes.
kepler-recovery-retirement-evidence:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    out=".gsd/evidence/kepler-k1/retirement-evidence.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.retirement-evidence.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    args=(
      --inventory .gsd/evidence/kepler-k1/inventory.json
      --retirement-paths .gsd/evidence/kepler-k1/retirement-paths.json
      --database-evidence .gsd/evidence/kepler-k1/database-manifest.json
    )
    if [ -f .gsd/evidence/kepler-k1/redis-evidence.json ]; then
      args+=(--redis-evidence .gsd/evidence/kepler-k1/redis-evidence.json)
    fi
    python3 modules/hosts/kepler/_collision_recovery_retirement_evidence.py "${args[@]}" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'retirement_evidence=%s\n' "$out"

# Render the exact retirement/disposition manifest from reviewed evidence.
kepler-recovery-retirement-plan evidence=".gsd/evidence/kepler-k1/retirement-evidence.json":
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    out=".gsd/evidence/kepler-k1/retirement-manifest.json"
    tmp="$(mktemp .gsd/evidence/kepler-k1/.retirement-manifest.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/kepler/_collision_recovery_retirement.py \
      .gsd/evidence/kepler-k1/inventory.json "{{evidence}}" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$out"
    trap - EXIT
    printf 'retirement_manifest=%s\nsha256=%s\n' "$out" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "$out")"

# Execute one reviewed retirement manifest after a fresh inventory hash match.
kepler-recovery-retirement-remote-verify manifest_sha256 inventory_sha256 manifest=".gsd/evidence/kepler-k1/retirement-manifest.json":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{manifest_sha256}}" =~ ^[0-9a-f]{64}$ && "{{inventory_sha256}}" =~ ^[0-9a-f]{64}$ ]] || {
      echo "invalid retirement binding" >&2
      exit 2
    }
    python3 - "{{manifest}}" "{{manifest_sha256}}" <<'PY'
    import json, pathlib, sys
    wrapper = json.loads(pathlib.Path(sys.argv[1]).read_text())
    if wrapper.get("manifest_sha256") != sys.argv[2]:
        raise SystemExit("retirement manifest SHA-256 mismatch")
    PY
    ssh -p 2222 erik@{{ip_kepler}} \
      'tmp=$(mktemp); trap '\''rm -f "$tmp"'\'' EXIT; cat >"$tmp"; kepler-collision-recovery-executor --manifest "$tmp" --manifest-sha256 "{{manifest_sha256}}" --inventory-sha256 "{{inventory_sha256}}"' \
      < "{{manifest}}"

# Execute one reviewed retirement manifest after a fresh inventory hash match.
kepler-recovery-retirement-execute manifest_sha256 inventory_sha256 manifest=".gsd/evidence/kepler-k1/retirement-manifest.json":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{manifest_sha256}}" =~ ^[0-9a-f]{64}$ && "{{inventory_sha256}}" =~ ^[0-9a-f]{64}$ ]] || {
      echo "invalid retirement binding" >&2
      exit 2
    }
    just kepler-recovery-inventory
    actual="$(python3 -c 'import json; print(json.load(open(".gsd/evidence/kepler-k1/inventory.json"))["inventory_sha256"])')"
    test "$actual" = "{{inventory_sha256}}" || { echo "retirement inventory drift" >&2; exit 2; }
    python3 - "{{manifest}}" "{{manifest_sha256}}" <<'PY'
    import json, pathlib, sys
    wrapper = json.loads(pathlib.Path(sys.argv[1]).read_text())
    if wrapper.get("manifest_sha256") != sys.argv[2]:
        raise SystemExit("retirement manifest SHA-256 mismatch")
    PY
    ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
    submission="$(ssh "${ssh_opts[@]}" erik@{{ip_kepler}} \
      'tmp=$(mktemp); trap '\''rm -f "$tmp"'\'' EXIT; cat >"$tmp"; kepler-collision-retirement-job submit "$tmp" "{{manifest_sha256}}" "{{inventory_sha256}}"' \
      < "{{manifest}}")"
    request_sha="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["request_sha256"])' <<<"$submission")"
    [[ "$request_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid retirement request binding" >&2; exit 2; }
    for _ in $(seq 1 120); do
      if status="$(ssh "${ssh_opts[@]}" erik@{{ip_kepler}} kepler-collision-retirement-job status "$request_sha")"; then
        state="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["state"])' <<<"$status")"
        case "$state" in
          passed)
            ssh "${ssh_opts[@]}" erik@{{ip_kepler}} kepler-collision-retirement-job result "$request_sha"
            exit 0
            ;;
          failed) echo "retirement job failed: $request_sha" >&2; exit 2 ;;
          pending|running) ;;
          *) echo "invalid retirement job state" >&2; exit 2 ;;
        esac
      fi
      sleep 5
    done
    echo "retirement job still remote: $request_sha" >&2
    exit 2

# Emergency exact retirement approved interactively; bypasses recovery evidence gates.
kepler-recovery-retirement-force-approved:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=10)
    host=erik@{{ip_kepler}}
    ssh "${ssh_opts[@]}" "$host" podman rm --force d4889db4a5883077f83f4236202f4294c8a2f6a492c36e7a1ffd45fd3c72bb87 2>/dev/null || true
    echo 'DONE container ha-train-run'
    ssh "${ssh_opts[@]}" "$host" podman rm --force 0916806c278662045d04b7f5a470c040b9b14dd6d6c5d022045c48b8e3e5423b 2>/dev/null || true
    echo 'DONE container minicpm-train'
    ssh "${ssh_opts[@]}" "$host" podman rm --force 8e61022a6b55484a9661aabb8be7c5d782e8fc2cdaee4c0963c7bb1015d32619 2>/dev/null || true
    echo 'DONE container uv_build'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /bulk/git
    echo 'DONE path /bulk/git'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/apps/gitlab/config
    echo 'DONE path /fast/apps/gitlab/config'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/apps/gitlab/logs
    echo 'DONE path /fast/apps/gitlab/logs'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/apps/gitlab-runner
    echo 'DONE path /fast/apps/gitlab-runner'
    ssh "${ssh_opts[@]}" "$host" sudo rm --one-file-system --recursive --force -- /fast/ai-models/f5-tts
    echo 'DONE artifact /fast/ai-models/f5-tts'
    ssh "${ssh_opts[@]}" "$host" podman image rm sha256:9a607634ac682f35bc1cd88bd7453bda11e9fdc5eb99afea3b23311d5e6f1a34 2>/dev/null || true
    echo 'DONE image gitlab'
    ssh "${ssh_opts[@]}" "$host" podman image rm sha256:3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b 2>/dev/null || true
    echo 'DONE image f5-tts'
    postgres=0146cb4f3b498654e247fca160fee2e1acfbe301d12b9a8285996a250f2686f9
    ssh "${ssh_opts[@]}" "$host" podman start "$postgres" >/dev/null
    sleep 15
    ssh "${ssh_opts[@]}" "$host" "podman exec '$postgres' sh -ceu 'exec dropdb --if-exists -U \"\$POSTGRES_USER\" airflow'"
    ssh "${ssh_opts[@]}" "$host" podman stop "$postgres" >/dev/null
    echo 'DONE database airflow'

# Exact full-container recreation approved for the Kepler recovery campaign.
kepler-recovery-reset-declared-approved:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh_opts=(-p 2222 -o BatchMode=yes -o ConnectTimeout=10)
    host=erik@{{ip_kepler}}
    containers=(
      0146cb4f3b498654e247fca160fee2e1acfbe301d12b9a8285996a250f2686f9
      ad3d3c02a8ea82090218d2e7e889a0b7c90410913ff65cc30f9f5d1db19bb434
      1088499c85881d0cd34c4bfd33174ff60cdc7af5425c5d0b35c596ece084f060
      306ee7200b6e0ccf8f7256bcd6e8d9fcf1032a6c91389ab727459506200ae728
      70af9b17b63a2eecb57ac1411440db631d21880e73718b6b00cd4f198f44f832
      84f32d8fe1b01e7f7be30cbe01034c80e95f689a1cff6e2437f22c8e24a9accc
      e055b76f6587be195f6fe5f2e455ed9d3115cbac6826fd0084b2a5703403abf1
      f9ee1a9901d5b3870d85218a64d112bbe9752542093e6dcd2241347f693acc2f
      a90e47f940e0ec80b8ac37be028064cd1d1db4fcc2705674b035f2920c42e4c3
      9314084a100d410926e5a6c9e1e6cf373fcfdcc88db5d7e4e85e3a76d2483462
      f28fdf964e96b0117f021ec73c1e028a0fd3116a92a960b70e515f58d55bec1c
      f9a131792be86483d3d950599192c4d717f0d8b366b469773534a67f8e5f6e8e
    )
    for id in "${containers[@]}"; do
      ssh "${ssh_opts[@]}" "$host" podman rm --force "$id"
      echo "DONE container $id"
    done
    ssh "${ssh_opts[@]}" "$host" podman volume rm homelab_redis_data
    echo 'DONE volume homelab_redis_data'
    ssh "${ssh_opts[@]}" "$host" podman volume rm infra_redis_data
    echo 'DONE volume infra_redis_data'

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

# Read-only evidence bundle for Discovery's boot-RAID migration. Never emits
# secret values; hashes identity files and reports only OpenBao seal metadata.
discovery-migration-inventory:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      echo ":: disks and stable IDs"
      lsblk -e7 -b -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS,MODEL,SERIAL,WWN
      find /dev/disk/by-id -maxdepth 1 -type l -printf "%f -> %l\n" | sort
      echo ":: mount graph"
      for mount in / /boot /home /nix /var/log /home/erik/vault; do
        findmnt -nro TARGET,SOURCE,FSTYPE,UUID "$mount" 2>/dev/null || true
      done
      echo ":: filesystem identity"
      sudo blkid
      echo ":: state size"
      sudo du -xsh /var/lib/docker /home/erik /home/erik/vault 2>/dev/null || true
      openbao_state="$(sudo readlink -f /var/lib/openbao)"
      printf "openbao-state=%s\n" "$openbao_state"
      sudo du -xsh "$openbao_state" 2>/dev/null || true
      echo ":: docker physical ownership"
      sudo docker info --format json | jq -r '"root=\(.DockerRootDir) driver=\(.Driver)"'
      sudo docker system df -v
      sudo docker volume ls -q | while read -r volume; do
        sudo docker volume inspect "$volume" | jq -r '.[0] | "\(.Name) \(.Mountpoint)"'
      done | sort
      echo ":: declared/runtime containers"
      sudo docker ps -a --format json | jq -r '[.Names, .State, .Status, .Image] | @tsv' | sort
      echo ":: critical host units"
      for unit in sshd tailscaled docker libvirtd openbao openbao-unseal vault-agent nfs-client.target; do
        printf "%s=" "$unit"
        systemctl is-active "$unit" 2>/dev/null || true
      done
      echo ":: OpenBao metadata"
      BAO_ADDR=http://127.0.0.1:8200 bao status 2>&1 | sed -n "/Initialized/p;/Sealed/p;/Storage Type/p;/Cluster Name/p;/HA Enabled/p"
      echo ":: backup evidence"
      systemctl list-timers --all --no-pager | grep -Ei "restic|vault|backup|tofu" || true
      sudo find /var/lib/vault-snapshots /home/erik/vault/restic -xdev -type f -printf "%TY-%Tm-%TdT%TH:%TM:%TS %s %p\n" 2>/dev/null | sort | tail -40
      echo ":: identity fingerprints"
      ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
      sudo sha256sum /var/lib/tailscale/tailscaled.state
      echo ":: DNS and edge probes"
      dig +time=3 +tries=1 @192.168.10.210 discovery.homelab.pastelariadev.com A
      curl -kfsS -o /dev/null -w "swag=%{http_code}\n" https://grafana.homelab.pastelariadev.com/
      echo ":: HAOS"
      sudo virsh list --all
      sudo virsh domblklist haos 2>/dev/null || true
      echo ":: failed units"
      systemctl --failed --no-legend || true
    REMOTE

# P1 SWAG adoption authorization is prepared offline from a previously captured,
# value-free inventory. Inventory is the only recipe that contacts Discovery;
# it runs the fixed read-only collector and validates the result locally.
discovery-swag-inventory output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_discovery}} \
      'sudo discovery-stateful-swag-inventory capture' >"$tmp"
    python3 modules/hosts/discovery/_stateful-swag-preflight.py plan "$tmp" >/dev/null
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-preflight inventory output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/discovery/_stateful-swag-preflight.py plan "{{inventory}}" >"$tmp"
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-result inventory authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 modules/hosts/discovery/_stateful-swag-preflight.py verify \
      "{{inventory}}" "{{authorization}}"

discovery-swag-execute authorization manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved manifest SHA-256' >&2; exit 1; }
    test -f "{{authorization}}" || { echo 'BLOCKED: authorization file absent' >&2; exit 1; }
    test "$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["manifest_sha256"])' "{{authorization}}")" = "$hash" || {
      echo 'BLOCKED: authorization file does not contain approved manifest SHA-256' >&2
      exit 1
    }
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo discovery-stateful-swag-adopt execute --authorization - --manifest-sha $hash" \
      <"{{authorization}}"

discovery-swag-rollback manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved manifest SHA-256' >&2; exit 1; }
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo discovery-stateful-swag-adopt rollback --manifest-sha $hash"

discovery-swag-recover-pre-adoption manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved manifest SHA-256' >&2; exit 1; }
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo discovery-stateful-swag-adopt recover-pre-adoption --manifest-sha $hash"

# P1 attempt-02 resumes only the post-recreate ownership correction. It binds
# the retained first-attempt evidence and current runtime before any recreate.
discovery-swag-resume-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" \
      "sudo stat -c '{\"device\":%d,\"inode\":%i,\"mode\":\"%a\",\"owner\":\"%u:%g\",\"type\":\"%F\"}' /home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini"

# Report only value-free current and completed P1 credential identity metadata.
discovery-swag-amendment-metadata-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      journal=/var/lib/stateful-stack-migrations/p1-swag/transition-b676063-amendment/metadata-state.json
      printf "stored="
      sudo jq -c "{device,inode,mode,uid,gid,regular,symlink}" "$journal"
      printf "current="
      credential=/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini
      regular=false
      symlink=false
      if sudo test -f "$credential" && ! sudo test -L "$credential"; then regular=true; fi
      if sudo test -L "$credential"; then symlink=true; fi
      sudo stat -c "{\"device\":%d,\"inode\":%i,\"mode\":\"%a\",\"uid\":%u,\"gid\":%g,\"regular\":$regular,\"symlink\":$symlink}" "$credential"
    '

discovery-swag-resume-observe output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_discovery}} \
      'sudo discovery-stateful-swag-adopt observe-attempt-02' >"$tmp"
    python3 modules/hosts/discovery/_stateful-swag-preflight.py resume-plan "$tmp" >/dev/null
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-resume-preflight observation output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/discovery/_stateful-swag-preflight.py resume-plan "{{observation}}" >"$tmp"
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-resume-result observation authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 modules/hosts/discovery/_stateful-swag-preflight.py resume-verify \
      "{{observation}}" "{{authorization}}"

discovery-swag-resume-execute authorization manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved resume manifest SHA-256' >&2; exit 1; }
    test -f "{{authorization}}" || { echo 'BLOCKED: resume authorization file absent' >&2; exit 1; }
    test "$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["manifest_sha256"])' "{{authorization}}")" = "$hash" || {
      echo 'BLOCKED: authorization file does not contain approved resume manifest SHA-256' >&2
      exit 1
    }
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo discovery-stateful-swag-adopt resume-attempt-02 --authorization - --manifest-sha $hash" \
      <"{{authorization}}"

# P1 attempt-03 only finalizes evidence and gates the already-recreated exact
# runtime. It performs no container lifecycle command.
discovery-swag-finalize-observe output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_discovery}} \
      'sudo discovery-stateful-swag-adopt observe-attempt-03' >"$tmp"
    python3 modules/hosts/discovery/_stateful-swag-preflight.py finalize-plan "$tmp" >/dev/null
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-finalize-preflight observation output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/discovery/_stateful-swag-preflight.py finalize-plan "{{observation}}" >"$tmp"
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-finalize-result observation authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 modules/hosts/discovery/_stateful-swag-preflight.py finalize-verify \
      "{{observation}}" "{{authorization}}"

discovery-swag-finalize-execute authorization manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved finalize manifest SHA-256' >&2; exit 1; }
    test -f "{{authorization}}" || { echo 'BLOCKED: finalize authorization file absent' >&2; exit 1; }
    test "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "{{authorization}}")" = "$hash" || {
      echo 'BLOCKED: authorization file does not contain approved finalize manifest SHA-256' >&2
      exit 1
    }
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo discovery-stateful-swag-adopt finalize-attempt-03 --authorization - --manifest-sha $hash" \
      <"{{authorization}}"

# P1 bounded Servarr transition: retire the tracked SWAG credential, recreate
# exactly swag-init + swag, and preserve the prior attempt evidence. The target
# render is computed without interpolation or environment resolution.
discovery-swag-transition-target-render:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="$(readlink -f references/repos/servarr)"
    test "$(git -C "$repo" rev-parse HEAD)" = b676063eafa53c00947c458d631493f98349f63c || {
      echo 'BLOCKED: local Servarr target commit differs' >&2
      exit 1
    }
    docker compose --project-name networking \
      --project-directory /home/erik/servarr/machines/discovery \
      -f "$repo/machines/discovery/networking.yml" \
      config --no-interpolate --no-env-resolution 2>/dev/null | sha256sum | awk '{print $1}'

# Value-free Git binding diagnostic; does not fetch, reset, or change the clone.
discovery-swag-transition-ref-status:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} '
      printf "head="; git -C /home/erik/servarr rev-parse HEAD
      printf "origin_main="; git -C /home/erik/servarr rev-parse refs/remotes/origin/main
      printf "remote_main="; git -C /home/erik/servarr ls-remote origin refs/heads/main | awk "{print \$1}"
      printf "git_dir="; git -C /home/erik/servarr rev-parse --git-dir
      printf "common_dir="; git -C /home/erik/servarr rev-parse --git-common-dir
      printf "branch="; git -C /home/erik/servarr symbolic-ref --short HEAD
      printf "fetch_refspec="; git -C /home/erik/servarr config --get-all remote.origin.fetch | paste -sd, -
      printf "deploy_branch="; if test -f /home/erik/servarr/.deploy-branch; then sed -n 1p /home/erik/servarr/.deploy-branch; else echo absent; fi
      git -C /home/erik/servarr fetch --dry-run --verbose origin refs/heads/main:refs/remotes/origin/main 2>&1
    '

discovery-swag-transition-render-status:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} '
      cd /home/erik/servarr/machines/discovery
      printf "with_env_files="
      sudo docker-compose --project-name networking --env-file .env --env-file /run/vault-agent/networking.env -f networking.yml config --no-interpolate --no-env-resolution 2>/dev/null | sha256sum | awk "{print \$1}"
      printf "without_env_files="
      sudo docker-compose --project-name networking -f networking.yml config --no-interpolate --no-env-resolution 2>/dev/null | sha256sum | awk "{print \$1}"
    '

# Value-free Certbot hook metadata: paths and file types only, never contents.
discovery-swag-transition-hook-status:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} '
      root=/home/erik/servarr/machines/discovery/config/swag/etc/letsencrypt/renewal-hooks
      sudo stat -c "d . %a %u:%g" "$root"
      sudo find "$root" -mindepth 1 -maxdepth 2 -printf "%y %P %m %U:%G\n" | LC_ALL=C sort
      sudo find "$root" -mindepth 2 -maxdepth 2 -type f -print0 | LC_ALL=C sort -z | sudo xargs -0 sha256sum
    '

discovery-swag-transition-observe output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    target_render="$(just discovery-swag-transition-target-render)"
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo discovery-stateful-swag-transition observe --target-render-sha $target_render" >"$tmp"
    python3 modules/hosts/discovery/_stateful-swag-transition.py plan "$tmp" >/dev/null
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-transition-preflight observation output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    python3 modules/hosts/discovery/_stateful-swag-transition.py plan "{{observation}}" >"$tmp"
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-transition-result observation authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    python3 modules/hosts/discovery/_stateful-swag-transition.py verify \
      "{{observation}}" "{{authorization}}"

discovery-swag-transition-execute observation authorization manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved transition manifest SHA-256' >&2; exit 1; }
    test -f "{{observation}}" -a -f "{{authorization}}" || { echo 'BLOCKED: transition artifacts absent' >&2; exit 1; }
    test "$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["manifest_sha256"])' "{{authorization}}")" = "$hash" || {
      echo 'BLOCKED: authorization file does not contain approved transition manifest SHA-256' >&2
      exit 1
    }
    bundle="$(mktemp -d)"
    trap 'rm -rf "$bundle"' EXIT
    install -m 0400 "{{observation}}" "$bundle/observation.json"
    install -m 0400 "{{authorization}}" "$bundle/authorization.json"
    tar -C "$bundle" -cf - observation.json authorization.json | \
      ssh -p 2222 erik@{{ip_discovery}} \
        "bundle=\$(mktemp -d); trap 'rm -rf \"\$bundle\"' EXIT; tar -C \"\$bundle\" -xf -; sudo discovery-stateful-swag-transition execute \"\$bundle/observation.json\" \"\$bundle/authorization.json\" --manifest-sha $hash"

# Amendment for the exact post-reset/pre-phase halt. The original transition
# journal remains immutable and is hash-bound as superseded evidence.
discovery-swag-transition-amendment-observe output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@{{ip_discovery}} \
      'sudo discovery-stateful-swag-transition-amendment observe' >"$tmp"
    SWAG_TRANSITION_BASE=modules/hosts/discovery/_stateful-swag-transition.py \
      python3 modules/hosts/discovery/_stateful-swag-transition-amendment.py plan "$tmp" >/dev/null
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-transition-amendment-preflight observation output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    SWAG_TRANSITION_BASE=modules/hosts/discovery/_stateful-swag-transition.py \
      python3 modules/hosts/discovery/_stateful-swag-transition-amendment.py plan "{{observation}}" >"$tmp"
    chmod 0400 "$tmp"
    mv "$tmp" "{{output}}"
    trap - EXIT
    sha256sum "{{output}}"

discovery-swag-transition-amendment-result observation authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    SWAG_TRANSITION_BASE=modules/hosts/discovery/_stateful-swag-transition.py \
      python3 modules/hosts/discovery/_stateful-swag-transition-amendment.py verify \
        "{{observation}}" "{{authorization}}"

discovery-swag-transition-amendment-execute observation authorization manifest-sha:
    #!/usr/bin/env bash
    set -euo pipefail
    hash='{{manifest-sha}}'
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo 'BLOCKED: invalid approved amendment manifest SHA-256' >&2; exit 1; }
    test -f "{{observation}}" -a -f "{{authorization}}" || { echo 'BLOCKED: amendment artifacts absent' >&2; exit 1; }
    test "$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text())["manifest_sha256"])' "{{authorization}}")" = "$hash" || {
      echo 'BLOCKED: authorization file does not contain approved amendment manifest SHA-256' >&2
      exit 1
    }
    bundle="$(mktemp -d)"
    trap 'rm -rf "$bundle"' EXIT
    install -m 0400 "{{observation}}" "$bundle/observation.json"
    install -m 0400 "{{authorization}}" "$bundle/authorization.json"
    tar -C "$bundle" -cf - observation.json authorization.json | \
      ssh -p 2222 erik@{{ip_discovery}} \
        "bundle=\$(mktemp -d); trap 'rm -rf \"\$bundle\"' EXIT; tar -C \"\$bundle\" -xf -; sudo discovery-stateful-swag-transition-amendment execute \"\$bundle/observation.json\" \"\$bundle/authorization.json\" --manifest-sha $hash"

# P2 read-only inventory. It records only allowlisted identities, metadata,
# booleans, counts, and probe statuses; it never emits credentials or payloads.
discovery-adguard-inventory output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-inventory capture' >"$tmp"
    P2_ADGUARD_TARGET_COMMIT=9969e35dca0cfb49a68bda3ba10156667cd4b53f \
      P2_ADGUARD_IMAGE_ADGUARD=adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927 \
      P2_ADGUARD_IMAGE_EXPORTER=ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1@sha256:42a9581bae4a91e6d4985415d1fe89ab9b1f50fbe2945a1c122d212d6354b747 \
      python3 modules/hosts/discovery/_stateful-adguard-preflight.py plan "$tmp" >/dev/null
    chmod 0400 "$tmp"
    ln "$tmp" "{{output}}"
    rm "$tmp"
    trap - EXIT
    sha256sum "{{output}}"

# Capture the same value-free inventory without planner validation.
discovery-adguard-inventory-raw output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '/run/wrappers/bin/sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-inventory capture' >"$tmp"
    chmod 0400 "$tmp"
    ln "$tmp" "{{output}}"
    rm "$tmp"
    trap - EXIT
    sha256sum "{{output}}"

discovery-adguard-preflight inventory output:
    #!/usr/bin/env bash
    set -euo pipefail
    test ! -e "{{output}}" || { echo "BLOCKED: output already exists: {{output}}" >&2; exit 1; }
    tmp="{{output}}.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    P2_ADGUARD_TARGET_COMMIT=9969e35dca0cfb49a68bda3ba10156667cd4b53f \
      P2_ADGUARD_IMAGE_ADGUARD=adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927 \
      P2_ADGUARD_IMAGE_EXPORTER=ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1@sha256:42a9581bae4a91e6d4985415d1fe89ab9b1f50fbe2945a1c122d212d6354b747 \
      python3 modules/hosts/discovery/_stateful-adguard-preflight.py plan "{{inventory}}" >"$tmp"
    chmod 0400 "$tmp"
    ln "$tmp" "{{output}}"
    rm "$tmp"
    trap - EXIT
    sha256sum "{{output}}"

discovery-adguard-result inventory authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    P2_ADGUARD_TARGET_COMMIT=9969e35dca0cfb49a68bda3ba10156667cd4b53f \
      P2_ADGUARD_IMAGE_ADGUARD=adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927 \
      P2_ADGUARD_IMAGE_EXPORTER=ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1@sha256:42a9581bae4a91e6d4985415d1fe89ab9b1f50fbe2945a1c122d212d6354b747 \
      python3 modules/hosts/discovery/_stateful-adguard-preflight.py verify \
        "{{inventory}}" "{{authorization}}"

# Prefetch and render the two exact published Servarr revisions while DNS is
# healthy. The installed helper is the only command allowed to fetch here.
discovery-adguard-revision-prefetch output:
    #!/usr/bin/env bash
    set -euo pipefail
    output={{ quote(output) }}
    test ! -e "$output" || { echo "BLOCKED: output already exists" >&2; exit 1; }
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      remote=/var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json
      cache=/home/erik/.cache/stateful-stack-migrations/p2-adguard
      pending=$cache/revision-prefetch.json.pending
      test ! -e "$pending" || { echo "BLOCKED: pending prefetch already exists" >&2; exit 1; }
      sudo -n /run/current-system/sw/bin/test ! -e "$remote" || { echo "BLOCKED: retained prefetch already exists" >&2; exit 1; }
      mkdir -p "$cache"
      chmod 0700 "$cache"
      helper=$(readlink -f "$(command -v servarr-exact-revision)")
      case "$helper" in
        /nix/store/*/bin/servarr-exact-revision) ;;
        *) echo "BLOCKED: exact revision helper is not Nix-store bound" >&2; exit 1 ;;
      esac
      trap '\''rm -f "$pending"'\'' EXIT
      "$helper" prefetch --output "$pending"
      sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-prefetch-publish
    '
    tmp="$output.tmp.$$"
    trap 'rm -f "$tmp"' EXIT
    ssh -p 2222 erik@"$IP" "sudo -n /run/current-system/sw/bin/cat /var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json" >"$tmp"
    chmod 0400 "$tmp"
    ln "$tmp" "$output"
    rm "$tmp"
    trap - EXIT
    sha256sum "$output"

# Retire only the reviewed invalid P2 revision prefetch after exact SHA match.
# The next prefetch recipe recreates it; no other migration evidence is touched.
discovery-adguard-revision-prefetch-retire-invalid expected_sha256:
    #!/usr/bin/env bash
    set -euo pipefail
    expected={{ quote(expected_sha256) }}
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "BLOCKED: invalid expected SHA-256" >&2; exit 1; }
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" "EXPECTED='$expected' bash -s" <<'REMOTE'
    set -euo pipefail
    path=/var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json
    actual=$(sudo -n /run/current-system/sw/bin/sha256sum "$path")
    actual=${actual%% *}
    test "$actual" = "$EXPECTED" || { echo 'BLOCKED: retained prefetch SHA-256 differs' >&2; exit 1; }
    sudo -n /run/current-system/sw/bin/rm -- "$path"
    REMOTE

# Retire only the exact P2 rollback deployment pin so normal origin/main pulls
# resume. This never touches Compose state, containers, volumes, or evidence.
discovery-adguard-retire-rollback-pin:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
    set -euo pipefail
    repo=/home/erik/servarr
    pin=$repo/.deploy-commit
    rollback=b676063eafa53c00947c458d631493f98349f63c
    test -f "$pin" || { echo 'BLOCKED: exact revision pin absent' >&2; exit 1; }
    jq -e --arg rollback "$rollback" '
      (keys | sort) == ["pin", "pin_sha256"] and
      (.pin | keys | sort) == ["commit", "render_sha256", "selection", "tree", "version"] and
      .pin.version == 1 and
      .pin.commit == $rollback and
      .pin.selection == "rollback" and
      (.pin.tree | test("^[0-9a-f]{40}$")) and
      (.pin.render_sha256 | test("^[0-9a-f]{64}$")) and
      (.pin_sha256 | test("^[0-9a-f]{64}$"))
    ' "$pin" >/dev/null || { echo 'BLOCKED: exact revision pin is not the P2 rollback' >&2; exit 1; }
    actual=$(jq -jcS .pin "$pin" | sha256sum)
    actual=${actual%% *}
    expected=$(jq -r .pin_sha256 "$pin")
    test "$actual" = "$expected" || { echo 'BLOCKED: exact revision pin hash differs' >&2; exit 1; }
    test "$(git -C "$repo" rev-parse HEAD)" = "$rollback" || { echo 'BLOCKED: checkout is not the pinned rollback' >&2; exit 1; }
    rm -- "$pin"
    REMOTE

# Build the value-free, exact P2 authorization candidate on Discovery so the
# installed Nix-store source hashes and retained revision prefetch are bound.
discovery-adguard-transition-plan inventory p3_manifest p3_observation p3_result prefetch output:
    #!/usr/bin/env bash
    set -euo pipefail
    inventory={{ quote(inventory) }}
    p3_manifest={{ quote(p3_manifest) }}
    p3_observation={{ quote(p3_observation) }}
    p3_result={{ quote(p3_result) }}
    prefetch={{ quote(prefetch) }}
    output={{ quote(output) }}
    test ! -e "$output" || { echo "BLOCKED: output already exists" >&2; exit 1; }
    IP="$(just _host-ip discovery)"
    bundle="$(mktemp -d)"
    tmp="$output.tmp.$$"
    cleanup() { rm -rf "$bundle"; rm -f "$tmp"; }
    trap cleanup EXIT
    install -m 0400 "$inventory" "$bundle/inventory.json"
    install -m 0400 "$p3_manifest" "$bundle/p3-manifest.json"
    install -m 0400 "$p3_observation" "$bundle/p3-observation.json"
    install -m 0400 "$p3_result" "$bundle/p3-result.json"
    install -m 0400 "$prefetch" "$bundle/revision-prefetch.json"
    tar -C "$bundle" -cf - . | ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      bundle=$(mktemp -d)
      trap '\''rm -rf "$bundle"'\'' EXIT
      tar -C "$bundle" -xf -
      sudo -n /run/current-system/sw/bin/cmp "$bundle/revision-prefetch.json" /var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json
      sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-transition plan \
        "$bundle/inventory.json" "$bundle/p3-manifest.json" \
        "$bundle/p3-observation.json" "$bundle/p3-result.json" \
        /var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json
    ' >"$tmp"
    jq -e '.manifest.approval_ready == true and .manifest.blockers == []' "$tmp" >/dev/null
    chmod 0400 "$tmp"
    ln "$tmp" "$output"
    rm "$tmp"
    trap - EXIT
    sha256sum "$output"

# Recompute every binding against the installed helper before approval/execution.
discovery-adguard-transition-verify inventory p3_manifest p3_observation p3_result authorization:
    #!/usr/bin/env bash
    set -euo pipefail
    inventory={{ quote(inventory) }}
    p3_manifest={{ quote(p3_manifest) }}
    p3_observation={{ quote(p3_observation) }}
    p3_result={{ quote(p3_result) }}
    authorization={{ quote(authorization) }}
    IP="$(just _host-ip discovery)"
    bundle="$(mktemp -d)"
    trap 'rm -rf "$bundle"' EXIT
    install -m 0400 "$inventory" "$bundle/inventory.json"
    install -m 0400 "$p3_manifest" "$bundle/p3-manifest.json"
    install -m 0400 "$p3_observation" "$bundle/p3-observation.json"
    install -m 0400 "$p3_result" "$bundle/p3-result.json"
    install -m 0400 "$authorization" "$bundle/authorization.json"
    tar -C "$bundle" -cf - . | ssh -p 2222 erik@"$IP" '
      set -euo pipefail
      bundle=$(mktemp -d)
      trap '\''rm -rf "$bundle"'\'' EXIT
      tar -C "$bundle" -xf -
      sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-transition verify \
        "$bundle/inventory.json" "$bundle/p3-manifest.json" \
        "$bundle/p3-observation.json" "$bundle/p3-result.json" \
        /var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json \
        "$bundle/authorization.json"
    '

# Execute only the exact approved manifest SHA. The executor re-inventories
# Discovery before the first mutation and retains every protection artifact.
discovery-adguard-transition-execute authorization manifest_sha256:
    #!/usr/bin/env bash
    set -euo pipefail
    authorization={{ quote(authorization) }}
    manifest_sha256={{ quote(manifest_sha256) }}
    [[ "$manifest_sha256" =~ ^[0-9a-f]{64}$ ]]
    test "$(jq -r .manifest_sha256 "$authorization")" = "$manifest_sha256"
    IP="$(just _host-ip discovery)"
    tar -C "$(dirname "$authorization")" -cf - "$(basename "$authorization")" | \
      ssh -p 2222 erik@"$IP" "
        set -euo pipefail
        bundle=\$(mktemp -d)
        trap 'rm -rf \"\$bundle\"' EXIT
        tar -C \"\$bundle\" -xf -
        remote_authorization=\$(find \"\$bundle\" -mindepth 1 -maxdepth 1 -type f -print -quit)
        test -n \"\$remote_authorization\"
        sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-transition execute \"\$remote_authorization\" \"$manifest_sha256\"
      "

# Report only value-free P2 phase state from the retained Discovery journal.
discovery-adguard-transition-status:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" \
      'path=/var/lib/stateful-stack-migrations/p2-adguard/journal.jsonl; if /run/wrappers/bin/sudo -n /run/current-system/sw/bin/test -e "$path"; then /run/wrappers/bin/sudo -n /run/current-system/sw/bin/cat "$path"; else printf '\''{"status":"not-started"}\n'\''; fi' | \
      jq -sc 'map({event,phase,status,error_class,recovery_failed})'

# Emergency exact-pair recovery after a retained P2 transition failure.
discovery-adguard-recover-current:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'cd /home/erik/servarr/machines/discovery && docker-compose --project-name networking --project-directory /home/erik/servarr/machines/discovery --env-file /home/erik/servarr/machines/discovery/.env --env-file /run/vault-agent/networking.env -f /home/erik/servarr/machines/discovery/networking.yml up -d --no-deps --force-recreate adguard adguard-exporter'

# Preserve one exact failed P2 attempt under its manifest hash before retry.
discovery-adguard-transition-retire-failed manifest_sha256:
    #!/usr/bin/env bash
    set -euo pipefail
    expected={{ quote(manifest_sha256) }}
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]]
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" "/run/wrappers/bin/sudo -n /run/current-system/sw/bin/bash -s -- '$expected'" <<'REMOTE'
    set -euo pipefail
    EXPECTED=$1
    root=/var/lib/stateful-stack-migrations
    base=$root/p2-adguard
    journal=$base/journal.jsonl
    dest=$base/superseded-$EXPECTED
    snapshot=/home/.snapshots/stateful-stack-p2-adguard
    snapshot_dest=/home/.snapshots/stateful-stack-p2-adguard-superseded-$EXPECTED
    /run/current-system/sw/bin/test -f "$journal"
    /run/current-system/sw/bin/grep -Fq "\"manifest_sha256\":\"$EXPECTED\"" "$journal"
    /run/current-system/sw/bin/grep -Fq '"status":"failed"' "$journal"
    /run/current-system/sw/bin/test ! -e "$dest"
    /run/current-system/sw/bin/mkdir -m 0700 "$dest"
    for name in authorization.json inventory.json work.tar.zst work.tar.zst.sha256 ledger.json phase-ledger.json restore-work forward-revision.json rollback-revision.json rollback.json artifact-index.json journal.jsonl revision-forward-authorization.json revision-rollback-authorization.json; do
      if /run/current-system/sw/bin/test -e "$base/$name"; then /run/current-system/sw/bin/mv -- "$base/$name" "$dest/$name"; fi
    done
    if /run/current-system/sw/bin/test -e "$snapshot"; then
      /run/current-system/sw/bin/test ! -e "$snapshot_dest"
      /run/current-system/sw/bin/mv -- "$snapshot" "$snapshot_dest"
    fi
    REMOTE

# Restore the exact pre-transition split state from one superseded attempt.
discovery-adguard-recover-superseded manifest_sha256:
    #!/usr/bin/env bash
    set -euo pipefail
    expected={{ quote(manifest_sha256) }}
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]]
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" "/run/wrappers/bin/sudo -n /run/current-system/sw/bin/bash -s -- '$expected'" <<'REMOTE'
    set -euo pipefail
    EXPECTED=$1
    root=/var/lib/stateful-stack-migrations
    base=$root/p2-adguard
    evidence=$base/superseded-$EXPECTED
    prefetch=$base/revision-prefetch.json
    helper=/run/current-system/sw/bin/servarr-exact-revision
    compose=/run/current-system/sw/bin/docker-compose
    root_mode=$(/run/current-system/sw/bin/stat -c %a "$root")
    base_mode=$(/run/current-system/sw/bin/stat -c %a "$base")
    rollback_output=/tmp/p2-adguard-$EXPECTED-manual-rollback.json
    forward_output=/tmp/p2-adguard-$EXPECTED-manual-forward.json
    trap '/run/current-system/sw/bin/chmod 0400 "$prefetch"; /run/current-system/sw/bin/chmod "$base_mode" "$base"; /run/current-system/sw/bin/chmod "$root_mode" "$root"; /run/current-system/sw/bin/chmod 0700 "$evidence"; /run/current-system/sw/bin/rm -f "$rollback_output" "$forward_output"' EXIT
    /run/current-system/sw/bin/test -f "$evidence/revision-rollback-authorization.json"
    /run/current-system/sw/bin/test -f "$evidence/revision-forward-authorization.json"
    /run/current-system/sw/bin/test ! -e "$evidence/manual-rollback-revision.json"
    /run/current-system/sw/bin/test ! -e "$evidence/manual-forward-revision.json"
    /run/current-system/sw/bin/chmod 0444 "$prefetch"
    /run/current-system/sw/bin/chmod 0755 "$root"
    /run/current-system/sw/bin/chmod 0755 "$base"
    /run/current-system/sw/bin/chmod 0755 "$evidence"
    /run/wrappers/bin/sudo -n -u erik -- "$helper" activate rollback --prefetch "$prefetch" --authorization "$evidence/revision-rollback-authorization.json" --output "$rollback_output"
    /run/wrappers/bin/sudo -n -u erik -- "$compose" --project-name networking --project-directory /home/erik/servarr/machines/discovery --env-file /home/erik/servarr/machines/discovery/.env --env-file /run/vault-agent/networking.env -f /home/erik/servarr/machines/discovery/networking.yml up -d --no-deps --force-recreate adguard adguard-exporter
    /run/wrappers/bin/sudo -n -u erik -- "$helper" activate forward --prefetch "$prefetch" --authorization "$evidence/revision-forward-authorization.json" --output "$forward_output"
    /run/current-system/sw/bin/install -m 0400 "$rollback_output" "$evidence/manual-rollback-revision.json"
    /run/current-system/sw/bin/install -m 0400 "$forward_output" "$evidence/manual-forward-revision.json"
    REMOTE

# Value-free exporter diagnostic: allowlisted family presence only.
discovery-adguard-exporter-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" \
      'sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-inventory exporter-families'

# One-time no-clobber cutover from the tracked live AdGuard YAML to the
# gitignored runtime bind. The migration helper is read from the exact reviewed
# Servarr commit and runs before pull-servarr can reset the legacy tracked file.
discovery-servarr-status-value-free:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'git -C /home/erik/servarr status --short --branch --untracked-files=no'

discovery-servarr-pull-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'systemctl --user --no-pager --full status servarr-pull.service || true; journalctl --user -u servarr-pull.service -n 30 --no-pager'

discovery-adguard-runtime-split servarr_commit:
    #!/usr/bin/env bash
    set -euo pipefail
    commit={{ quote(servarr_commit) }}
    branch=feat/adguard-runtime-yaml-split
    inventory_ready() {
      local IP=$1
      local attempt
      for attempt in $(seq 1 30); do
        if ssh -p 2222 erik@"$IP" 'sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-inventory capture >/dev/null 2>/dev/null'; then
          return 0
        fi
        sleep 1
      done
      echo 'BLOCKED: AdGuard inventory did not become ready within 30 seconds' >&2
      return 1
    }
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'BLOCKED: Servarr commit must be a full SHA-1' >&2; exit 1; }
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" "EXPECTED='$commit' BRANCH='$branch' bash -s" <<'REMOTE'
    set -euo pipefail
    repo=/home/erik/servarr
    legacy=$repo/machines/discovery/config/adguard/AdGuardHome.yaml
    runtime=$repo/machines/discovery/runtime/adguard/AdGuardHome.yaml
    helper=machines/discovery/scripts/init-adguard-runtime.sh
    cd "$repo"
    if test -f "$legacy"; then
      test "$(git ls-files --error-unmatch machines/discovery/config/adguard/AdGuardHome.yaml)" = machines/discovery/config/adguard/AdGuardHome.yaml
      helper_source=$legacy
    else
      sudo -n test -f "$runtime"
      sudo -n test ! -L "$runtime"
      test "$(sudo -n stat -c %a "$runtime")" = 600
      helper_source=$runtime
    fi
    mount_source=$(docker inspect adguard | jq -er '.[0].Mounts[] | select(.Destination == "/opt/adguardhome/conf") | .Source')
    case "$mount_source" in
      "$repo/machines/discovery/config/adguard"|"$repo/machines/discovery/runtime/adguard") ;;
      *) echo 'BLOCKED: unexpected AdGuard config bind source' >&2; exit 1 ;;
    esac
    test "$(docker inspect adguard | jq -er '.[0].Config.Labels | .["com.docker.compose.project"] + "/" + .["com.docker.compose.service"]')" = networking/adguard
    test "$(docker inspect adguard-exporter | jq -er '.[0].Config.Labels | .["com.docker.compose.project"] + "/" + .["com.docker.compose.service"]')" = networking/adguard-exporter
    git fetch origin "$BRANCH"
    test "$(git rev-parse "origin/$BRANCH^{commit}")" = "$EXPECTED" || { echo 'BLOCKED: branch tip differs from approved commit' >&2; exit 1; }
    tmp=$(mktemp)
    trap 'rm -f "$tmp" "$tmp.target-paths"' EXIT
    git show "$EXPECTED:$helper" >"$tmp"
    chmod 0500 "$tmp"
    runtime_preexisting=false
    sudo -n test -e "$runtime" && runtime_preexisting=true
    sudo -n "$tmp" "$helper_source" "$runtime"
    sudo -n test -f "$runtime"
    sudo -n test ! -L "$runtime"
    test "$(sudo -n stat -c %a "$runtime")" = 600
    if ! $runtime_preexisting; then
      sudo -n /run/current-system/sw/bin/cmp -s "$helper_source" "$runtime"
    fi
    if ! git diff --quiet -- . ':(exclude)machines/discovery/config/adguard/AdGuardHome.yaml'; then
      approved_tree=false
      git diff --name-only HEAD "$EXPECTED" >"$tmp.target-paths"
      if ! git diff --name-only | grep -Fvx -f "$tmp.target-paths" >/dev/null; then
        approved_tree=true
        while IFS= read -r path; do
          if git diff --quiet -- "$path" && git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
            continue
          fi
          if blob=$(git rev-parse "$EXPECTED:$path" 2>/dev/null); then
            test ! -e "$path" || { test -f "$path" && test "$(git hash-object "$path")" = "$blob"; } || approved_tree=false
          else
            test ! -e "$path" || approved_tree=false
          fi
        done <"$tmp.target-paths"
      fi
      $approved_tree || { echo 'BLOCKED: deployed Servarr checkout has unapproved tracked changes' >&2; exit 1; }
    fi
    git diff --cached --quiet || { echo 'BLOCKED: deployed Servarr checkout has staged changes' >&2; exit 1; }
    REMOTE
    just pull-servarr discovery "$branch"
    ssh -p 2222 erik@"$IP" "EXPECTED='$commit' bash -s" <<'REMOTE'
    set -euo pipefail
    repo=/home/erik/servarr
    runtime=$repo/machines/discovery/runtime/adguard/AdGuardHome.yaml
    cd "$repo"
    test "$(git rev-parse HEAD)" = "$EXPECTED"
    sudo -n test -f "$runtime"
    sudo -n test ! -L "$runtime"
    test "$(sudo -n stat -c %a "$runtime")" = 600
    test "$(git check-ignore -q machines/discovery/runtime/adguard/AdGuardHome.yaml; echo $?)" = 0
    cd machines/discovery
    docker-compose --project-name networking --project-directory "$PWD" --env-file .env --env-file /run/vault-agent/networking.env -f networking.yml config >/dev/null
    REMOTE
    just discovery-adguard-recover-current
    ssh -p 2222 erik@"$IP" 'test "$(docker inspect adguard | jq -er '\''.[0].Mounts[] | select(.Destination == "/opt/adguardhome/conf") | .Source'\'')" = /home/erik/servarr/machines/discovery/runtime/adguard'
    inventory_ready "$IP"
    just discovery-adguard-recover-current
    ssh -p 2222 erik@"$IP" 'test "$(docker inspect adguard | jq -er '\''.[0].Mounts[] | select(.Destination == "/opt/adguardhome/conf") | .Source'\'')" = /home/erik/servarr/machines/discovery/runtime/adguard'
    inventory_ready "$IP"
    echo ':: AdGuard runtime split passed two value-free smoke cycles'

# Roll back declarations to one exact prior Servarr commit. The gitignored
# runtime YAML is retained; no YAML, volume, container data, or evidence is removed.
discovery-adguard-runtime-split-rollback prior_commit:
    #!/usr/bin/env bash
    set -euo pipefail
    commit={{ quote(prior_commit) }}
    inventory_ready() {
      local IP=$1
      local attempt
      for attempt in $(seq 1 30); do
        if ssh -p 2222 erik@"$IP" 'sudo -n /run/current-system/sw/bin/discovery-stateful-adguard-inventory capture >/dev/null 2>/dev/null'; then
          return 0
        fi
        sleep 1
      done
      echo 'BLOCKED: AdGuard inventory did not become ready within 30 seconds' >&2
      return 1
    }
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'BLOCKED: prior commit must be a full SHA-1' >&2; exit 1; }
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" "EXPECTED='$commit' bash -s" <<'REMOTE'
    set -euo pipefail
    cd /home/erik/servarr
    git fetch origin main
    git merge-base --is-ancestor "$EXPECTED" origin/main || { echo 'BLOCKED: prior commit is not on origin/main' >&2; exit 1; }
    test "$(git rev-parse 'origin/main^{commit}')" = "$EXPECTED" || { echo 'BLOCKED: origin/main differs from approved prior commit' >&2; exit 1; }
    printf '%s\n' main >.deploy-branch
    REMOTE
    just pull-servarr discovery main
    ssh -p 2222 erik@"$IP" "test \"\$(git -C /home/erik/servarr rev-parse HEAD)\" = '$commit'" || {
      echo 'BLOCKED: origin/main does not equal approved prior commit' >&2
      exit 1
    }
    just discovery-adguard-recover-current
    inventory_ready "$IP"
    echo ':: rollback passed; runtime YAML retained'

# Build Discovery's generated disko script without executing it, then prove the
# destructive set contains exactly the two reviewed Kingston SSDs and no vault
# identity or volatile sdX path.
discovery-esp-graph-proof:
    #!/usr/bin/env bash
    set -euo pipefail
    script=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.discovery.config.system.build.diskoScript \
      --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 0 | tail -1)
    primary="ata-KINGSTON_SA400S37480G_AA000000000000000105"
    mirror="ata-KINGSTON_SA400S37480G_AA000000000000000098"
    for expected in "$primary" "$mirror" "$mirror-part1"; do
      grep -Fq "$expected" "$script"
    done
    forbidden=(
      /dev/sda /dev/sdb /dev/sdc
      ST4000DM004 ZTT25R4M d026033d-158d-49ca-9ff9-dd2d5c8a21dc
    )
    for token in "${forbidden[@]}"; do
      if grep -Fq "$token" "$script"; then
        echo ":: BLOCKED: destructive graph contains $token" >&2
        exit 1
      fi
    done
    devices=$(sed -n 's/^for dev in \(.*\);/\1/p' "$script")
    expected_devices="/dev/disk/by-id/$mirror /dev/disk/by-id/$primary"
    test "$devices" = "$expected_devices" || {
      echo ":: BLOCKED: unexpected destructive devices: $devices" >&2
      exit 1
    }
    sha256sum "$script"
    echo ":: PASS: destructive graph contains only $devices"

# Read-only physical-identity gate. This must agree with the generated graph
# immediately before any future destructive approval.
discovery-esp-live-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      primary=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105)
      primary_boot=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part1)
      primary_root=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part2)
      mirror=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098)
      mirror_part=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098-part1)
      vault=$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M)
      vault_part=$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M-part1)
      test "$primary" != "$mirror"
      test "$primary" != "$vault"
      test "$mirror" != "$vault"
      test "$(findmnt -nro SOURCE /boot)" = "$primary_boot"
      test "$(findmnt -nro SOURCE / | sed 's/\[.*//')" = "$primary_root"
      test "$(findmnt -nro SOURCE /home/erik/vault)" = "$vault_part"
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      test "$(findmnt -nro SOURCE -T /var/lib/docker | sed 's/\[.*//')" = "$primary_root"
      sudo btrfs filesystem usage -b / | grep -Eq '^Data,RAID1:'
      sudo btrfs filesystem usage -b / | grep -Eq '^Metadata,RAID1:'
      printf "primary=%s mirror=%s vault=%s\n" "$primary" "$mirror" "$vault"
      for mount in /boot / /home/erik/vault /var/lib/docker; do
        findmnt -nro TARGET,SOURCE,FSTYPE,UUID -T "$mount"
      done
      sudo btrfs filesystem show /
    REMOTE
    echo ":: PASS: live Discovery identities match reviewed graph; Docker is on destructive RAID"

# Seed Discovery's recovery copy while Docker remains online. This is only the
# bulk first pass; a later maintenance-window recipe must stop writers and run
# the final sync. Exit 24 means live files vanished during traversal and is
# expected here, but every other rsync failure blocks.
discovery-docker-mirror-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-esp-live-preflight
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      vault=/home/erik/vault
      destination=$vault/migration/discovery-docker-root
      test "$(findmnt -nro UUID "$vault")" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      available=$(findmnt -bnro AVAIL "$vault")
      source_bytes=$(sudo du -xsb /var/lib/docker | awk '{print $1}')
      required=$((source_bytes * 6 / 5))
      test "$available" -ge "$required" || {
        printf ':: BLOCKED: vault free=%s required=%s\n' "$available" "$required" >&2
        exit 1
      }
      sudo install -d -m 0700 -o root -g root "$vault/migration" "$destination"
      set +e
      sudo rsync -aHAXx --numeric-ids --delete-delay --stats \
        /var/lib/docker/ "$destination/"
      status=$?
      set -e
      case "$status" in 0|24) ;; *) exit "$status" ;; esac
      sudo find "$destination" -xdev -mindepth 1 -printf . | wc -c | awk '{print "mirror_entries=" $1}'
      sudo du -xsb "$destination" | awk '{print "mirror_bytes=" $1}'
      printf 'source_bytes=%s\nrsync_status=%s\nseeded_at=%s\n' \
        "$source_bytes" "$status" "$(date --iso-8601=seconds)"
    REMOTE
    echo ":: PASS: online Docker mirror seed complete; final stopped sync still required"

# Read-only Orion capacity/path gate before creating the isolated restore.
discovery-docker-scratch-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} \
      "sudo du -xsb /home/erik/vault/migration/discovery-docker-root | cut -f1")
    ssh -p 2222 erik@{{ip_orion}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      scratch=/projects/recovery/discovery-esp/docker-root
      test ! -e "$scratch"
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 6 / 5))
      test "$available" -ge "$required" || {
        printf ':: BLOCKED: /projects free=%s required=%s\n' "$available" "$required" >&2
        exit 1
      }
      printf 'source_bytes=%s available=%s required=%s scratch=%s\n' \
        "$SOURCE_BYTES" "$available" "$required" "$scratch"
    REMOTE
    echo ":: PASS: Orion /projects scratch target is absent and has capacity"

# Pull the static vault mirror into Orion using root rsync at both endpoints.
# SSH still runs as erik, reusing the Nix-managed host key without forwarding it.
discovery-docker-scratch-restore:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-docker-scratch-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 \
      | grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      scratch=/projects/recovery/discovery-esp/docker-root
      pending=$scratch.pending
      known_hosts=$(mktemp)
      trap 'rm -f "$known_hosts"' EXIT
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      test ! -e "$scratch"
      sudo install -d -m 0700 -o root -g root "$(dirname "$scratch")" "$pending"
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' \
        -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/migration/discovery-docker-root/ "$pending/"
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete \
        --rsync-path='sudo rsync' \
        -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/migration/discovery-docker-root/ "$pending/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      sudo mv "$pending" "$scratch"
      sudo du -xsb "$scratch"
    REMOTE
    echo ":: PASS: Discovery Docker mirror restored exactly to Orion scratch"

# Refresh a previously proven scratch tree. Unpublish it while rsync applies the
# delta, then republish only after the second dry-run reports zero changes.
discovery-docker-scratch-refresh:
    #!/usr/bin/env bash
    set -euo pipefail
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 \
      | grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      scratch=/projects/recovery/discovery-esp/docker-root
      pending=$scratch.pending
      known_hosts=$(mktemp)
      trap 'rm -f "$known_hosts"' EXIT
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      if sudo test -e "$scratch"; then
        sudo test ! -e "$pending"
        sudo mv "$scratch" "$pending"
      else
        sudo test -d "$pending"
      fi
      available=$(findmnt -bnro AVAIL -T /projects)
      test "$available" -ge 21474836480 || {
        printf ':: BLOCKED: /projects free=%s minimum=21474836480\n' "$available" >&2
        exit 1
      }
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' \
        -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/migration/discovery-docker-root/ "$pending/"
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete \
        --rsync-path='sudo rsync' \
        -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/migration/discovery-docker-root/ "$pending/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      sudo mv "$pending" "$scratch"
      sudo du -xsb "$scratch"
    REMOTE
    echo ":: PASS: Orion scratch refreshed exactly from current Discovery mirror"

# Preserve container metadata, then make only the disposable scratch tree safe
# to open: no restart policies and no container marked running.
discovery-docker-scratch-quiesce:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      data=/projects/recovery/discovery-esp/docker-root
      archive_dir=/projects/recovery/discovery-esp/metadata-backups
      archive=$archive_dir/docker-container-metadata-$(date -u +%Y%m%dT%H%M%SZ).tar
      sudo test -d "$data/containers"
      sudo install -d -m 0700 -o root -g root "$archive_dir"
      sudo env DATA="$data" ARCHIVE="$archive" bash -s <<'ROOT'
        set -euo pipefail
        cd "$DATA"
        mapfile -d '' configs < <(find containers -mindepth 2 -maxdepth 2 -name config.v2.json -print0 | sort -z)
        mapfile -d '' hosts < <(find containers -mindepth 2 -maxdepth 2 -name hostconfig.json -print0 | sort -z)
        config_count=${#configs[@]}
        host_count=${#hosts[@]}
        test "$config_count" -gt 0
        test "$config_count" = "$host_count"
        tar -cf "$ARCHIVE" "${configs[@]}" "${hosts[@]}"
        for file in "${hosts[@]}"; do
          tmp=$(mktemp --tmpdir="$(dirname "$file")" .hostconfig.XXXXXX)
          jq '.RestartPolicy = {"Name":"no","MaximumRetryCount":0}' "$file" >"$tmp"
          chown --reference="$file" "$tmp"
          chmod --reference="$file" "$tmp"
          mv "$tmp" "$file"
        done
        for file in "${configs[@]}"; do
          tmp=$(mktemp --tmpdir="$(dirname "$file")" .config.XXXXXX)
          jq '.State.Running = false
            | .State.Paused = false
            | .State.Restarting = false
            | .State.Pid = 0
            | .HasBeenManuallyStopped = true' "$file" >"$tmp"
          chown --reference="$file" "$tmp"
          chmod --reference="$file" "$tmp"
          mv "$tmp" "$file"
        done
        printf 'configs=%s hosts=%s\n' "$config_count" "$host_count"
        sha256sum "$ARCHIVE"
    ROOT
    REMOTE
    echo ":: PASS: scratch container metadata archived and restart-disabled"

# Open the restored tree with a short-lived Docker daemon inside a networkless
# systemd namespace. Never expose its socket or start containers manually.
discovery-docker-scratch-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-docker-scratch-quiesce
    dockerd=$(nix eval --raw \
      .#nixosConfigurations.orion.config.virtualisation.docker.package.outPath)/bin/dockerd
    ssh -p 2222 erik@{{ip_orion}} "DOCKERD=$dockerd bash -s" <<'REMOTE'
      set -euo pipefail
      unit=discovery-docker-scratch.service
      data=/projects/recovery/discovery-esp/docker-root
      runtime=/run/discovery-docker-scratch
      socket=$runtime/docker.sock
      sudo test -d "$data"
      sudo systemctl stop "$unit" >/dev/null 2>&1 || true
      sudo install -d -m 0700 -o root -g root "$runtime"
      trap 'sudo systemctl stop "$unit" >/dev/null 2>&1 || true' EXIT
      sudo systemd-run --unit="${unit%.service}" --collect --service-type=exec \
        --property=PrivateNetwork=yes \
        --property=IPAddressDeny=any \
        "$DOCKERD" \
        --data-root="$data" \
        --exec-root="$runtime/exec" \
        --pidfile="$runtime/docker.pid" \
        --host="unix://$socket" \
        --bridge=none \
        --iptables=false \
        --ip-forward=false \
        --ip-masq=false \
        --userland-proxy=false
      api() {
        sudo curl --fail --silent --show-error --max-time 3 \
          --unix-socket "$socket" "http://localhost$1"
      }
      ready=false
      for _ in $(seq 1 60); do
        if test "$(api /_ping 2>/dev/null || true)" = OK; then
          ready=true
          break
        fi
        sleep 1
      done
      if ! "$ready"; then
        sudo systemctl status "$unit" --no-pager -l || true
        sudo journalctl -u "$unit" -n 80 --no-pager
        exit 1
      fi
      containers_json=$(api '/containers/json?all=1')
      images_json=$(api /images/json)
      volumes_json=$(api /volumes)
      containers=$(jq length <<<"$containers_json")
      images=$(jq length <<<"$images_json")
      volumes=$(jq '.Volumes | length' <<<"$volumes_json")
      test "$containers" -gt 0
      test "$images" -gt 0
      test "$volumes" -gt 0
      printf 'containers=%s images=%s volumes=%s\n' "$containers" "$images" "$volumes"
      jq -r '.[] | [.Names[0], .State, .Status] | @tsv' \
        <<<"$containers_json" | sort | head -20
      sudo systemctl stop "$unit"
      trap - EXIT
      test "$(systemctl is-active "$unit" 2>/dev/null || true)" = inactive
    REMOTE
    echo ":: PASS: isolated Orion daemon opened restored Docker metadata"

# Stream a fresh full-cluster dump to Orion, restore it into a networkless
# disposable PostgreSQL container, and print metadata counts only.
discovery-postgres-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    if ! ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'; then
      ssh-keygen -lf "$scan" -E sha256
      exit 1
    fi
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      image='postgres:18.4@sha256:3a82e1f56c8f0f5616a11103ac3d47e632c3938698946a7ad26da0df1334744a'
      stamp=$(date +%Y-%m-%d_%H%M%S)
      evidence="/projects/recovery/discovery-esp/postgres/$stamp"
      dump="$evidence/postgres-all.sql.gz"
      name="discovery-postgres-drill-$stamp"
      known_hosts=$(mktemp)
      started=$(date +%s)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      sudo install -d -m 0700 -o root -g root "$evidence"
      trap 'rm -f "$known_hosts"; sudo docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
      ssh -n -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$known_hosts" erik@{{ip_discovery}} '
        set -euo pipefail
        cd /home/erik/servarr/machines/discovery
        user=$(sed -n "s/^POSTGRES_USER=//p" .env | tail -1)
        test -n "$user"
        sudo docker exec postgres pg_dumpall -U "$user"
      ' | gzip | sudo tee "$dump" >/dev/null
      sudo test -s "$dump"
      sudo gzip -t "$dump"
      sudo docker image inspect "$image" >/dev/null 2>&1 || sudo docker pull "$image"
      sudo docker run -d --network none --name "$name" \
        -e POSTGRES_PASSWORD=drill-only "$image" >/dev/null
      ready=false
      for _ in $(seq 1 60); do
        if sudo docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 1
      done
      "$ready"
      sudo gzip -dc "$dump" |
        sudo docker exec -i "$name" psql -v ON_ERROR_STOP=1 -U postgres postgres >/dev/null
      roles=$(sudo docker exec "$name" psql -AtU postgres postgres \
        -c 'SELECT count(*) FROM pg_roles')
      databases=$(sudo docker exec "$name" psql -AtU postgres postgres \
        -c "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY 1")
      test -n "$databases"
      {
        printf 'roles=%s\n' "$roles"
        while IFS= read -r database; do
          extensions=$(sudo docker exec "$name" psql -AtU postgres "$database" \
            -c 'SELECT count(*) FROM pg_extension')
          tables=$(sudo docker exec "$name" psql -AtU postgres "$database" \
            -c "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema')")
          rows=$(sudo docker exec "$name" psql -AtU postgres "$database" \
            -c 'SELECT coalesce(sum(n_live_tup),0)::bigint FROM pg_stat_user_tables')
          printf 'database=%s extensions=%s tables=%s representative_rows=%s\n' \
            "$database" "$extensions" "$tables" "$rows"
        done <<<"$databases"
        sudo sha256sum "$dump"
        printf 'dump=%s duration_seconds=%s\n' "$dump" "$(( $(date +%s) - started ))"
      } | sudo tee "$evidence/result.txt"
      sudo chmod 0600 "$evidence/result.txt"
    REMOTE
    echo ":: PASS: full PostgreSQL dump restored and inspected on isolated Orion"

# Print the newest value-free PostgreSQL drill report.
discovery-postgres-restore-drill-result:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} '
      latest=$(sudo find /projects/recovery/discovery-esp/postgres -mindepth 2 -maxdepth 2 -name result.txt -printf "%T@ %p\n" | sort -nr | head -1 | cut -d" " -f2-)
      test -n "$latest"
      sudo cat "$latest"
    '

# Prove the declared Redis cache layer starts empty without restored state.
discovery-redis-cold-start-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      image='redis:8.8.0-alpine@sha256:9d317178eceac8454a2284a9e6df2466b93c745529947f0cd42a0fa9609d7005'
      name="discovery-redis-drill-$(date +%s)"
      trap 'sudo docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
      sudo docker image inspect "$image" >/dev/null 2>&1 || sudo docker pull "$image"
      sudo docker run -d --network none --name "$name" "$image" \
        redis-server --requirepass drill-only >/dev/null
      ready=false
      for _ in $(seq 1 30); do
        if sudo docker exec "$name" redis-cli -a drill-only PING 2>/dev/null |
          grep -qx PONG; then
          ready=true
          break
        fi
        sleep 1
      done
      "$ready"
      sudo docker inspect "$name" |
        jq -e '.[0].HostConfig.NetworkMode == "none"' >/dev/null
      for database in 0 1 2 3 4; do
        keys=$(sudo docker exec "$name" redis-cli -a drill-only -n "$database" DBSIZE 2>/dev/null)
        test "$keys" = 0
        printf 'database=%s keys=%s\n' "$database" "$keys"
      done
    REMOTE
    echo ":: PASS: isolated Redis cold-started empty; no production state restored"

# Copy SWAG state and validate nginx/certificates on networkless Orion.
discovery-swag-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    openssl=$(nix eval --raw .#nixosConfigurations.orion.pkgs.openssl.outPath)/bin/openssl
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    if ! ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'; then
      ssh-keygen -lf "$scan" -E sha256
      exit 1
    fi
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys OPENSSL=$openssl bash -s" <<'REMOTE'
      set -euo pipefail
      image='lscr.io/linuxserver/swag:5.6.0-ls467@sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d'
      stamp=$(date +%Y-%m-%d_%H%M%S)
      evidence="/projects/recovery/discovery-esp/swag/$stamp"
      config="$evidence/config"
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      echo ":: prepare"
      sudo install -d -m 0700 -o root -g root "$config"
      echo ":: rsync"
      set +e
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/config/swag/ "$config/"
      status=$?
      set -e
      case "$status" in 0|24) ;; *) exit "$status" ;; esac
      printf 'rsync_status=%s\n' "$status"
      for route in harbor grafana; do
        printf 'route=%s\n' "$route"
        sudo test -s "$config/nginx/proxy-confs/$route.subdomain.conf"
      done
      mapfile -t fullchains < <(sudo find -L "$config/etc/letsencrypt/live" \
        -type f -name fullchain.pem -print)
      printf 'fullchains=%s\n' "${#fullchains[@]}"
      if test "${#fullchains[@]}" = 0; then
        sudo find "$config" -maxdepth 6 \( -name fullchain.pem -o -name privkey.pem \) -print
      fi
      test "${#fullchains[@]}" -gt 0
      for fullchain in "${fullchains[@]}"; do
        privkey="$(dirname "$fullchain")/privkey.pem"
        sudo test -s "$privkey"
        sudo "$OPENSSL" x509 -checkend 604800 -noout -in "$fullchain"
        cert_key=$(sudo "$OPENSSL" x509 -in "$fullchain" -pubkey -noout |
          "$OPENSSL" pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)
        private_key=$(sudo "$OPENSSL" pkey -in "$privkey" -pubout -outform DER |
          sha256sum | cut -d' ' -f1)
        test "$cert_key" = "$private_key"
      done
      sudo docker image inspect "$image" >/dev/null 2>&1 || sudo docker pull "$image"
      echo ":: nginx -t"
      sudo docker run --rm --network none --entrypoint /usr/sbin/nginx \
        -v "$config:/config" "$image" \
        -t -c /config/nginx/nginx.conf
      proxy_count=$(sudo find "$config/nginx/proxy-confs" -type f \
        -name '*.subdomain.conf' | wc -l)
      manifest=$(sudo find "$config" -xdev -printf '%P\t%y\t%s\t%m\t%U\t%G\n' |
        LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      printf 'nginx=valid certificates=%s key_match=true proxy_configs=%s manifest_sha256=%s\n' \
        "${#fullchains[@]}" "$proxy_count" "$manifest" | sudo tee "$evidence/result.txt"
      sudo chmod 0600 "$evidence/result.txt"
    REMOTE
    echo ":: PASS: copied SWAG config and certificate validate on networkless Orion"

# Read-only, value-free evidence for a Harbor activation failure.
harbor-iam-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -u
    systemctl status harbor.service --no-pager -l || true
    systemctl show harbor.service -p ActiveState -p SubState -p Result -p NRestarts
    journalctl -u harbor.service -b --no-pager -n 160 -o short-iso || true
    printf '%s\n' ':: active installer'
    if test -L /home/erik/servarr/machines/discovery/.harbor-installer/current; then
      readlink /home/erik/servarr/machines/discovery/.harbor-installer/current
    else
      printf '%s\n' absent
    fi
    printf '%s\n' ':: harbor containers'
    sudo docker ps -a --format json |
      jq -r 'select((.Names // "") | test("harbor|registry")) |
        [.Names, .State, .Status, .Image] | @tsv'
    REMOTE

# Report only whether Harbor's database owns a non-empty admin credential.
harbor-admin-credential-diagnostic:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    sudo docker exec harbor-db psql -X -U postgres -d registry -Atqc \
      "SELECT json_build_object(
        'admin_rows', count(*),
        'salt_present', coalesce(bool_and(length(salt) > 0), false),
        'password_present', coalesce(bool_and(length(password) > 0), false),
        'password_version', max(password_version)
      ) FROM harbor_user WHERE username = 'admin';"
    REMOTE

# Reset only Harbor's DB-backed admin credential to the rendered Vault value.
harbor-admin-password-recover snapshot_id confirmation="":
    #!/usr/bin/env bash
    set -euo pipefail
    snapshot_id={{ quote(snapshot_id) }}
    confirmation={{ quote(confirmation) }}
    [[ $snapshot_id =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
    [[ $confirmation == "reset-db-admin-password" ]] || {
      echo "confirmation must equal reset-db-admin-password" >&2
      exit 64
    }
    ssh -p 2222 erik@{{ip_orion}} bash -s -- "$snapshot_id" <<'REMOTE'
    set -euo pipefail
    target="/projects/recovery/harbor-iam/$1"
    test -d "$target"
    cd "$target"
    sha256sum --check --status SHA256SUMS
    REMOTE
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
    set -euo pipefail
    updated=$(sudo docker exec harbor-db psql -X -U postgres -d registry -Atqc \
      "WITH reset AS (
        UPDATE harbor_user SET salt = '', password = ''
        WHERE user_id = 1 AND username = 'admin'
        RETURNING user_id
      ) SELECT count(*) FROM reset;")
    test "$updated" = 1
    sudo docker restart harbor-core >/dev/null
    ready=false
    for _ in $(seq 1 60); do
      if curl -fsS http://127.0.0.1:8085/api/v2.0/health >/dev/null; then
        ready=true
        break
      fi
      sleep 2
    done
    $ready
    REMOTE
    just harbor-iam-preflight vault
    state=$(just harbor-admin-credential-diagnostic)
    jq -e '
      .admin_rows == 1 and
      .salt_present == true and
      .password_present == true and
      .password_version == "pbkdf2_sha256"
    ' <<<"$state" >/dev/null
    echo "Harbor admin credential recovered from the Vault-rendered value"

# Emit only the Harbor IAM metadata needed to decide whether OIDC migration is safe.
harbor-iam-preflight source="vault":
    #!/usr/bin/env bash
    set -euo pipefail
    source={{ quote(source) }}
    case "$source" in
      vault) env_file=/run/vault-agent/harbor.env ;;
      fallback) env_file=/home/erik/servarr/machines/discovery/.env ;;
      *) echo "source must be vault|fallback" >&2; exit 64 ;;
    esac
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo /run/current-system/sw/bin/bash -s -- --env-file $env_file" \
      < scripts/harbor-iam-preflight.sh

# Capture the pre-mutation Harbor database and sanitized auth metadata on Orion.
harbor-iam-snapshot:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    chmod 700 "$tmp"
    snapshot_id=$(date -u +%Y%m%dT%H%M%SZ)
    target="/projects/recovery/harbor-iam/$snapshot_id"

    just harbor-iam-preflight >"$tmp/harbor-auth.json"
    ssh -p 2222 erik@{{ip_discovery}} \
      'sudo docker exec harbor-db pg_dumpall -U postgres' \
      | gzip -9 >"$tmp/harbor-db.sql.gz"
    chmod 0600 "$tmp/harbor-auth.json" "$tmp/harbor-db.sql.gz"
    (cd "$tmp" && sha256sum harbor-auth.json harbor-db.sql.gz >SHA256SUMS)
    chmod 0600 "$tmp/SHA256SUMS"

    ssh -p 2222 erik@{{ip_orion}} bash -s -- "$target" <<'REMOTE'
    set -euo pipefail
    target=$1
    test ! -e "$target"
    sudo install -d -m 0700 -o erik -g users "$target"
    REMOTE
    scp -P 2222 "$tmp/harbor-auth.json" "$tmp/harbor-db.sql.gz" \
      "$tmp/SHA256SUMS" "erik@{{ip_orion}}:$target/"
    ssh -p 2222 erik@{{ip_orion}} bash -s -- "$target" <<'REMOTE'
    set -euo pipefail
    target=$1
    chmod 0600 "$target/harbor-auth.json" "$target/harbor-db.sql.gz" \
      "$target/SHA256SUMS"
    cd "$target"
    sha256sum --check SHA256SUMS
    REMOTE
    printf 'snapshot_id=%s target=%s\n' "$snapshot_id" "$target"

# Consume a mode-0600 Authentik bootstrap handoff into Sops and Kubernetes.
bootstrap-authentik handoff="authentik-bootstrap.secrets.json":
    scripts/bootstrap-authentik.sh {{quote(handoff)}}

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

# Create, validate, or remove the private provider handoff for Harbor IAM IaC.
harbor-iam-bootstrap-provider-handoff action="create" handoff="harbor-iam-bootstrap-provider.secrets.json":
    bash scripts/harbor-iam-provider-handoff.sh {{quote(action)}} {{quote(handoff)}} {{ip_discovery}}

# Read-only Harbor state/identity/capacity gate before copying vault data.
discovery-harbor-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      state=/home/erik/vault/harbor
      installer=/home/erik/servarr/machines/discovery/.harbor-installer/current
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      sudo test -d "$state"
      test -d "$installer"
      systemctl is-active --quiet harbor.service
      bytes=$(sudo du -xsb "$state" | cut -f1)
      printf 'state_bytes=%s\n' "$bytes" >&2
      du -sb "$installer" | awk '{print "installer_bytes=" $1}' >&2
      sudo docker ps -a --format json |
        jq -r 'select((.Names // "") | test("harbor|registry")) | [.Names, .State, .Image] | @tsv' >&2
      printf '%s\n' "$bytes"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_orion}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      target=/projects/recovery/discovery-esp/harbor
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 6 / 5))
      test "$available" -ge "$required"
      printf 'source_bytes=%s available=%s required=%s target=%s\n' \
        "$SOURCE_BYTES" "$available" "$required" "$target"
    REMOTE
    echo ":: PASS: Harbor vault state identified and Orion has restore capacity"

# Seed Harbor vault state + generated installer onto Orion while Harbor runs.
discovery-harbor-restore-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-harbor-restore-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/harbor
      state=$root/state
      installer=$root/installer
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      sudo test ! -e "$state"
      sudo test ! -e "$installer"
      sudo install -d -m 0700 -o root -g root "$state" "$installer"
      set +e
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/harbor/ "$state/"
      state_status=$?
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/.harbor-installer/current/ "$installer/"
      installer_status=$?
      set -e
      case "$state_status" in 0|24) ;; *) exit "$state_status" ;; esac
      case "$installer_status" in 0|24) ;; *) exit "$installer_status" ;; esac
      sudo du -xsb "$state" | awk '{print "state_bytes=" $1}'
      sudo du -xsb "$installer" | awk '{print "installer_bytes=" $1}'
      printf 'state_rsync_status=%s installer_rsync_status=%s\n' \
        "$state_status" "$installer_status"
    REMOTE
    echo ":: PASS: online Harbor restore seed complete; stopped final sync required"

# Briefly stop only Harbor, take the final exact delta, then always restart it.
discovery-harbor-restore-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      state=/projects/recovery/discovery-esp/harbor/state
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      options=(-p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
      remote_shell="sudo -H -u erik ssh ${options[*]}"
      sudo test -d "$state"
      resume() {
        ssh -n "${options[@]}" erik@{{ip_discovery}} \
          'sudo systemctl start harbor.service' >/dev/null 2>&1 || true
        rm -f "$known_hosts"
      }
      trap resume EXIT
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
        systemctl is-active --quiet harbor.service
        sudo systemctl stop harbor.service
        test "$(systemctl is-active harbor.service 2>/dev/null || true)" = inactive
      '
      started=$(date +%s)
      sudo rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/harbor/ "$state/"
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/vault/harbor/ "$state/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      ssh -n "${options[@]}" erik@{{ip_discovery}} 'sudo systemctl start harbor.service'
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        healthy=false
        for _ in $(seq 1 60); do
          if curl --fail --silent --max-time 3 http://127.0.0.1:8085/api/v2.0/health |
            jq -e ".status == \"healthy\"" >/dev/null 2>&1; then
            healthy=true
            break
          fi
          sleep 1
        done
        "$healthy"
        systemctl is-active harbor.service
      '
      trap - EXIT
      rm -f "$known_hosts"
      printf 'final_sync_seconds=%s drift=zero\n' "$(( $(date +%s) - started ))"
    REMOTE
    echo ":: PASS: Harbor final copy is exact and production API recovered"

# Print only generated Harbor topology needed to design an isolated boot.
discovery-harbor-restore-inspect:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      installer=/projects/recovery/discovery-esp/harbor/installer
      sudo test -f "$installer/docker-compose.yml"
      sudo docker compose -f "$installer/docker-compose.yml" config --format json |
        jq -c '
          .services | to_entries[] |
          {
            service: .key,
            image: .value.image,
            mounts: [.value.volumes[]? | {type, source, target}],
            ports: [.value.ports[]? | {target, published, protocol}],
            networks: (.value.networks // {})
          }'
    REMOTE

# Rebuild copied Harbor state on loopback, then pull, push, and delete a scratch tag.
discovery-harbor-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'sudo bash -s' <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/harbor
      source_installer=$root/installer
      installer=$root/drill-installer
      state=$root/state
      tag="discovery-esp-drill-$(date +%s)"
      export COMPOSE_PROJECT_NAME=discovery-harbor-drill
      cleanup() {
        test -z "${authfile:-}" || rm -f "$authfile"
        cd "$installer" 2>/dev/null &&
          sudo -E docker compose down --remove-orphans >/dev/null 2>&1 || true
      }
      trap cleanup EXIT
      sudo test -d "$state"
      sudo test -x "$source_installer/prepare"
      sudo rm -rf "$installer"
      sudo cp -a "$source_installer" "$installer"
      sudo chown -R erik:users "$installer"
      cd "$installer"
      sed -i \
        -e 's|^hostname:.*|hostname: harbor-drill.invalid|' \
        -e 's|^  port: 8085$|  port: 18085|' \
        -e "s|^data_volume:.*|data_volume: $state|" \
        -e "s|^    location:.*|    location: $root/log|" \
        harbor.yml
      if grep -q '^external_url:' harbor.yml; then
        sed -i 's|^external_url:.*|external_url: http://127.0.0.1:18085|' harbor.yml
      fi
      sudo install -d -m 0700 "$root/log"
      bash ./prepare
      awk '
        /^    logging:$/ { skip=1; next }
        skip && (/^[^ ]/ || /^  [^ ]/ || /^    [[:alnum:]_-]+:/) { skip=0 }
        !skip
      ' docker-compose.yml >docker-compose.yml.tmp
      mv docker-compose.yml.tmp docker-compose.yml
      sed -i \
        -e 's|18085:8080|127.0.0.1:18085:8080|' \
        docker-compose.yml
      sudo -E docker compose up -d
      healthy=false
      for _ in $(seq 1 120); do
        if curl --fail --silent --max-time 3 \
          http://127.0.0.1:18085/api/v2.0/health |
          jq -e '.status == "healthy"' >/dev/null 2>&1; then
          healthy=true
          break
        fi
        sleep 1
      done
      "$healthy"
      password=$(sed -n 's/^harbor_admin_password:[[:space:]]*//p' harbor.yml)
      test -n "$password"
      auth="admin:$password"
      image=library/kindle-dash
      source="docker://127.0.0.1:18085/$image:v0.3.4"
      target="docker://127.0.0.1:18085/$image:$tag"
      authfile=$(mktemp)
      rm -f "$authfile"
      printf '%s' "$password" |
        podman login --authfile "$authfile" --tls-verify=false \
          -u admin --password-stdin 127.0.0.1:18085 >/dev/null
      source=${source#docker://}
      target=${target#docker://}
      podman pull --authfile "$authfile" --tls-verify=false "$source" >/dev/null
      podman tag "$source" "$target"
      podman push --authfile "$authfile" --tls-verify=false "$target" >/dev/null
      podman rmi "$target" >/dev/null
      podman pull --authfile "$authfile" --tls-verify=false "$target" >/dev/null
      curl --fail --silent -o /dev/null -u "$auth" \
        http://127.0.0.1:18085/api/v2.0/system/gc/schedule
      curl --fail --silent -u "$auth" -X DELETE \
        "http://127.0.0.1:18085/api/v2.0/projects/library/repositories/kindle-dash/artifacts/$tag"
      rm -f "$authfile"
      status=$(sudo -E docker compose ps)
      printf '%s\n' "$status"
      ! grep -Fq '0.0.0.0:18085' <<<"$status"
    REMOTE
    echo ":: PASS: isolated Harbor restored; auth, pull, push, delete, and GC metadata passed"

# Read-only identity/capacity/tooling gate before cloning the HAOS disk.
discovery-haos-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      printf 'vault_uuid=%s vm_state=%s qemu_img=%s\n' \
        "$(findmnt -nro UUID /home/erik/vault)" \
        "$(sudo virsh domstate haos 2>/dev/null || true)" \
        "$(command -v qemu-img || true)" >&2
      sudo virsh domblklist haos --details >&2
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo virsh domstate haos)" = running
      disk=$(sudo virsh domblklist haos --details |
        awk '$1 == "file" && $2 == "disk" { print $4 }')
      test -n "$disk"
      sudo test -f "$disk"
      bytes=$(sudo stat -c %s "$disk")
      printf 'disk=%s virtual=%s bytes=%s\n' \
        "$disk" "$(sudo qemu-img info --force-share --output json "$disk" | jq -r '."virtual-size"')" "$bytes" >&2
      printf '%s\n' "$bytes"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_orion}} \
      "SOURCE_BYTES=$source_bytes QEMU_IMG=$qemu/bin/qemu-img QEMU_SYSTEM=$qemu/bin/qemu-system-x86_64 bash -s" <<'REMOTE'
      set -euo pipefail
      printf 'qemu_img=%s qemu_system=%s projects_avail=%s\n' \
        "$([[ -x "$QEMU_IMG" ]] && echo yes || echo no)" \
        "$([[ -x "$QEMU_SYSTEM" ]] && echo yes || echo no)" \
        "$(findmnt -bnro AVAIL -T /projects 2>/dev/null || true)" >&2
      test -x "$QEMU_IMG"
      test -x "$QEMU_SYSTEM"
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 6 / 5))
      test "$available" -ge "$required"
      printf 'source_bytes=%s available=%s required=%s\n' \
        "$SOURCE_BYTES" "$available" "$required"
    REMOTE
    echo ":: PASS: HAOS disk identified and Orion has clone/boot capacity"

# Seed the HAOS QCOW2 onto Orion while the production VM remains online.
discovery-haos-restore-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-haos-restore-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/haos
      target=$root/haos_ova-17.1.qcow2
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      sudo test ! -e "$target"
      sudo install -d -m 0700 -o root -g root "$root"
      sudo rsync -aHAXS --numeric-ids --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/srv/vms/haos_ova-17.1.qcow2 "$target"
      sudo stat -c 'bytes=%s blocks=%b mode=%a uid=%U gid=%G' "$target"
    REMOTE
    echo ":: PASS: online HAOS clone seed complete; stopped final sync required"

# Gracefully stop HAOS, finalize its exact clone, always restart, then check clone.
discovery-haos-restore-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} \
      "HOSTKEYS=$hostkeys QEMU_IMG=$qemu/bin/qemu-img bash -s" <<'REMOTE'
      set -euo pipefail
      target=/projects/recovery/discovery-esp/haos/haos_ova-17.1.qcow2
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      options=(-p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts")
      remote_shell="sudo -H -u erik ssh ${options[*]}"
      printf 'clone=' >&2
      sudo stat -c 'bytes=%s mode=%a' "$target" >&2 || true
      printf 'remote_vm_state=' >&2
      ssh -n "${options[@]}" erik@{{ip_discovery}} \
        'sudo virsh domstate haos 2>/dev/null || true' >&2
      sudo test -f "$target"
      resume() {
        ssh -n "${options[@]}" erik@{{ip_discovery}} \
          'sudo virsh start haos >/dev/null 2>&1 || true'
        rm -f "$known_hosts"
      }
      trap resume EXIT
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
        test "$(sudo virsh domstate haos)" = running
        sudo virsh shutdown haos
        stopped=false
        for _ in $(seq 1 300); do
          if test "$(sudo virsh domstate haos 2>/dev/null || true)" = "shut off"; then
            stopped=true
            break
          fi
          sleep 1
        done
        "$stopped"
      '
      started=$(date +%s)
      sudo rsync -aHAXS --inplace --numeric-ids --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/srv/vms/haos_ova-17.1.qcow2 "$target"
      drift=$(sudo rsync -aHAXSni --inplace --numeric-ids \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/srv/vms/haos_ova-17.1.qcow2 "$target")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      ssh -n "${options[@]}" erik@{{ip_discovery}} 'sudo virsh start haos'
      ssh -n "${options[@]}" erik@{{ip_discovery}} '
        set -euo pipefail
        healthy=false
        for _ in $(seq 1 180); do
          if curl --fail --silent --max-time 3 \
            http://192.168.10.115:8123/ >/dev/null 2>&1; then
            healthy=true
            break
          fi
          sleep 1
        done
        "$healthy"
        test "$(sudo virsh domstate haos)" = running
      '
      trap - EXIT
      rm -f "$known_hosts"
      sudo "$QEMU_IMG" check "$target"
      printf 'final_sync_seconds=%s drift=zero\n' "$(( $(date +%s) - started ))"
    REMOTE
    echo ":: PASS: HAOS exact clone is healthy and production VM recovered"

# Read-only completion gate after final sync/restart; never starts or stops HAOS.
discovery-haos-restore-result:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    ssh -p 2222 erik@{{ip_orion}} "QEMU_IMG=$qemu/bin/qemu-img bash -s" <<'REMOTE'
      set -euo pipefail
      target=/projects/recovery/discovery-esp/haos/haos_ova-17.1.qcow2
      sudo "$QEMU_IMG" check "$target"
    REMOTE
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      test "$(sudo virsh domstate haos)" = running
      healthy=false
      for _ in $(seq 1 600); do
        if curl --fail --silent --max-time 3 \
          http://192.168.10.115:8123/ >/dev/null 2>&1; then
          healthy=true
          break
        fi
        sleep 1
      done
      "$healthy"
    REMOTE
    echo ":: PASS: HAOS clone integrity and production health recovered"

# Boot the copied HAOS disk read-only on Orion with no network device.
discovery-haos-boot-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    qemu=$(nix eval --raw .#nixosConfigurations.orion.pkgs.qemu.outPath)
    ssh -p 2222 erik@{{ip_orion}} \
      "sudo QEMU=$qemu/bin/qemu-system-x86_64 FIRMWARE=$qemu/share/qemu bash -s" <<'REMOTE'
      set -euo pipefail
      disk=/projects/recovery/discovery-esp/haos/haos_ova-17.1.qcow2
      work=$(mktemp -d /projects/recovery/discovery-esp/haos/boot.XXXXXX)
      pidfile=$work/qemu.pid
      log=$work/console.log
      cleanup() {
        test ! -s "$pidfile" || kill "$(cat "$pidfile")" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT
      test -x "$QEMU"
      test -f "$FIRMWARE/edk2-x86_64-code.fd"
      test -f "$FIRMWARE/edk2-i386-vars.fd"
      test -f "$disk"
      cp "$FIRMWARE/edk2-i386-vars.fd" "$work/OVMF_VARS.fd"
      "$QEMU" \
        -name discovery-haos-restore-drill \
        -machine pc,accel=kvm \
        -cpu host -m 4096 -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file="$FIRMWARE/edk2-x86_64-code.fd" \
        -drive if=pflash,format=raw,file="$work/OVMF_VARS.fd" \
        -device virtio-scsi-pci,id=scsi0 \
        -drive file="$disk",format=qcow2,if=none,id=disk0 \
        -device scsi-hd,drive=disk0,bus=scsi0.0 \
        -nic none -snapshot -display none -monitor none \
        -serial file:"$log" -daemonize -pidfile "$pidfile"
      booted=false
      for _ in $(seq 1 300); do
        if grep -Eq 'Home Assistant Operating System|Welcome to Home Assistant|ha >' "$log"; then
          booted=true
          break
        fi
        test -s "$pidfile" && kill -0 "$(cat "$pidfile")"
        sleep 1
      done
      "$booted"
      grep -E 'Home Assistant Operating System|Welcome to Home Assistant|ha >' "$log" | tail -5
      kill "$(cat "$pidfile")"
      wait "$(cat "$pidfile")" 2>/dev/null || true
      trap - EXIT
      printf 'network=none disk=snapshot boot=passed\n'
    REMOTE
    echo ":: PASS: copied HAOS reached console boundary with no network"

# Read-only sample/capacity inventory before encrypted mutable-state backup.
discovery-home-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      fixed=(
        /home/erik/.config/sops/age/keys.txt
        /etc/ssh/ssh_host_ed25519_key
      )
      for path in "${fixed[@]}" \
        /home/erik/servarr \
        /home/erik/servarr/machines/discovery/config/swag; do
        if sudo test -e "$path"; then
          printf 'exists=%s\n' "$path" >&2
        else
          printf 'missing=%s\n' "$path" >&2
        fi
      done
      for path in "${fixed[@]}"; do sudo test -s "$path"; done
      for root in \
        /home/erik/servarr \
        /home/erik/servarr/machines/discovery/config/swag; do
        sudo test -d "$root"
        sudo find "$root" -xdev -type f -size +0c -printf '%s %p\n' |
          sort -nr | sed -n '1p' >&2
      done
      sudo find /home/erik/servarr/machines/discovery/config/swag \
        -type f -name '*.pem' -printf 'pem=%p\n' | sort | tail -10 >&2
      sudo find /home/erik/Documents -xdev -type f -size +0c \
        -printf '%s %p\n' | sort -nr | sed -n '1p' >&2
      sudo find /home/erik -xdev -type f -size +1G \
        -printf '%s %p\n' | sort -nr | sed -n '1p' >&2
      bytes=$(sudo du -xsb /home/erik /etc/ssh | awk '{sum += $1} END {print sum}')
      printf 'source_bytes=%s\n' "$bytes" >&2
      printf '%s\n' "$bytes"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_kepler}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      available=$(findmnt -bnro AVAIL -T /bulk)
      test "$available" -ge "$SOURCE_BYTES"
      printf 'source_bytes=%s available=%s target=/bulk/backups/discovery-esp-home\n' \
        "$SOURCE_BYTES" "$available"
    REMOTE
    echo ":: PASS: mutable-state restore classes exist and Kepler has capacity"

# Encrypt Discovery's host identities to Kepler and verify the restored hashes.
backup-discovery-identity-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    DISCOVERY="{{ip_discovery}}"
    KEPLER="{{ip_kepler}}"
    samples=(
      var/lib/tailscale/tailscaled.state
      etc/ssh/ssh_host_ed25519_key
      home/erik/.config/sops/age/keys.txt
    )
    password_file=$(mktemp)
    hashes=$(mktemp)
    restore=$(mktemp -d)
    trap 'rm -f "$password_file" "$hashes"; rm -rf "$restore"' EXIT
    ssh -p 2222 erik@"$DISCOVERY" \
      'sudo cat /run/secrets/vault_restic_password' >"$password_file"
    chmod 0600 "$password_file"
    export RESTIC_PASSWORD_FILE="$password_file"
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/discovery-esp-home"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    restic unlock
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$DISCOVERY" "sudo sha256sum '/$sample'" >>"$hashes"
    done
    ssh -p 2222 erik@"$DISCOVERY" \
      "sudo tar -C / -cpf - ${samples[*]}" |
      restic backup --stdin --stdin-filename discovery-host-identity.tar \
        --tag discovery-esp-identity
    snapshot=$(restic snapshots --tag discovery-esp-identity --latest 1 --json |
      jq -r 'max_by(.time).short_id')
    restic dump "$snapshot" discovery-host-identity.tar |
      tar -xpf - -C "$restore"
    while read -r expected path; do
      actual=$(sha256sum "$restore/${path#/}" | awk '{print $1}')
      test "$actual" = "$expected"
    done <"$hashes"
    printf 'snapshot=%s tailscale_sha256=%s verified_at=%s\n' \
      "$snapshot" "$(awk '$2 == "/var/lib/tailscale/tailscaled.state" {print $1}' "$hashes")" \
      "$(date --iso-8601=seconds)"
    echo ":: PASS: encrypted Discovery host identities restored and hash-verified"

# Restore the pinned D5 host-identity snapshot before stateful services resume.
restore-discovery-identity-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    DISCOVERY="{{ip_discovery}}"
    KEPLER="{{ip_kepler}}"
    snapshot=868abf42
    tailscale_sha256=c6a64318c4b5685b513056d22be3d91c25ae810d6d793c7a9fe400a22ff97c93
    ssh_fingerprint='SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    password_file=$(mktemp)
    restore=$(mktemp -d)
    trap 'rm -f "$password_file"; rm -rf "$restore"' EXIT
    ssh -p 2222 erik@"$DISCOVERY" \
      'sudo cat /run/secrets/vault_restic_password' >"$password_file"
    chmod 0600 "$password_file"
    export RESTIC_PASSWORD_FILE="$password_file"
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/discovery-esp-home"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    restic dump "$snapshot" discovery-host-identity.tar | tar -xpf - -C "$restore"
    test "$(sha256sum "$restore/var/lib/tailscale/tailscaled.state" | awk '{print $1}')" = "$tailscale_sha256"
    test "$(ssh-keygen -yf "$restore/etc/ssh/ssh_host_ed25519_key" |
      ssh-keygen -lf - -E sha256 | awk '{print $2}')" = "$ssh_fingerprint"
    ssh -p 2222 erik@"$DISCOVERY" '
      sudo systemctl stop tailscaled-autoconnect.service tailscaled.service || true
      sudo systemctl stop haos-vm.service docker.service docker.socket \
        libvirtd.service openbao.service vault-agent.service || true
    '
    tar -C "$restore" -cpf - etc/ssh var/lib/tailscale home/erik/.config/sops |
      ssh -p 2222 erik@"$DISCOVERY" 'sudo tar -C / -xpf -'
    ssh -p 2222 erik@"$DISCOVERY" "TAILSCALE_SHA256=$tailscale_sha256 SSH_FINGERPRINT=$ssh_fingerprint bash -s" <<'REMOTE'
      set -euo pipefail
      sudo chmod 0600 /etc/ssh/ssh_host_ed25519_key /var/lib/tailscale/tailscaled.state
      sudo chown -R erik:users /home/erik/.config/sops
      sudo chmod 0600 /home/erik/.config/sops/age/keys.txt
      sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key |
        sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null
      sudo chmod 0644 /etc/ssh/ssh_host_ed25519_key.pub
      test "$(sudo sha256sum /var/lib/tailscale/tailscaled.state | awk '{print $1}')" = "$TAILSCALE_SHA256"
      test "$(sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256 | awk '{print $2}')" = "$SSH_FINGERPRINT"
      sudo /run/current-system/activate
      sudo systemctl restart tailscaled.service
      sudo systemctl restart sshd.service
      test "$(tailscale status --json | jq -r .BackendState)" = Running
    REMOTE
    echo ":: PASS: Discovery SSH, Tailscale, and sops identities restored"

# Verify the new boot storage and preserved vault before state restoration.
verify-discovery-postinstall-storage:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      esp=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part1)
      primary=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part2)
      mirror=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098-part1)
      vault=$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M-part1)
      for mount in /boot /home/erik/vault; do
        findmnt -nro TARGET,SOURCE,FSTYPE,UUID "$mount"
      done
      sudo btrfs filesystem show /
      sudo btrfs filesystem usage -b /
      systemctl is-active docker.service libvirtd.service openbao.service || true
      test "$(findmnt -nro SOURCE /boot)" = "$esp"
      test "$(findmnt -bnro SIZE /boot)" -ge 2000000000
      test "$(findmnt -nro FSTYPE /boot)" = vfat
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(findmnt -nro SOURCE /home/erik/vault)" = "$vault"
      devices=$(sudo btrfs filesystem show /)
      grep -Fq "path $primary" <<<"$devices"
      grep -Fq "path $mirror" <<<"$devices"
      sudo btrfs filesystem usage -b / | grep -Eq "^Data,RAID1:"
      sudo btrfs filesystem usage -b / | grep -Eq "^Metadata,RAID1:"
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active libvirtd.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active openbao.service 2>/dev/null || true)" = inactive
    REMOTE
    echo ":: PASS: Discovery ESP, Btrfs RAID1, and vault identities verified"

# Restore the pinned D5 mutable-state archive, then re-apply Home Manager.
restore-discovery-home-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    DISCOVERY="{{ip_discovery}}"
    KEPLER="{{ip_kepler}}"
    snapshot=6943b508
    password_file=$(mktemp)
    trap 'rm -f "$password_file"' EXIT
    ssh -p 2222 erik@"$DISCOVERY" 'bash -s' <<'REMOTE'
      set -euo pipefail
      sudo systemctl stop haos-vm.service docker.service docker.socket \
        libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket \
        openbao.service vault-agent.service || true
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active libvirtd.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active openbao.service 2>/dev/null || true)" = inactive
    REMOTE
    ssh -p 2222 erik@"$DISCOVERY" \
      'sudo cat /run/secrets/vault_restic_password' >"$password_file"
    chmod 0600 "$password_file"
    export RESTIC_PASSWORD_FILE="$password_file"
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/discovery-esp-home"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    restic snapshots "$snapshot" >/dev/null
    restic dump "$snapshot" discovery-mutable-state.tar |
      ssh -p 2222 erik@"$DISCOVERY" 'sudo tar -C / -xpf -'
    ssh -p 2222 erik@"$DISCOVERY" 'bash -s' <<'REMOTE'
      set -euo pipefail
      for path in \
        /home/erik/.config/sops/age/keys.txt \
        /home/erik/servarr/machines/discovery/.env.sops \
        /home/erik/servarr/machines/discovery/config/swag/nginx/proxy-confs/harbor.subdomain.conf \
        /home/erik/servarr/README.md; do
        sudo test -s "$path"
      done
      test "$(sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256 | awk '{print $2}')" = \
        'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
      sudo systemctl restart home-manager-erik.service
      systemctl is-active --quiet home-manager-erik.service
    REMOTE
    echo ":: PASS: Discovery mutable home and SSH state restored from 6943b508"

# Hold stateful substrates down across dependency-triggered restarts.
quiesce-discovery-restore:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      units=(
        haos-vm.service
        docker.service docker.socket docker-recover.service docker-recover.timer
        libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
        openbao.service openbao-unseal.service openbao-unseal.timer
        vault-agent.service
      )
      sudo systemctl mask --runtime --now "${units[@]}"
      sudo systemctl stop "${units[@]}" || true
      sudo systemctl reset-failed "${units[@]}" || true
      for unit in docker.service libvirtd.service openbao.service vault-agent.service; do
        test "$(systemctl is-active "$unit" 2>/dev/null || true)" = inactive
      done
    REMOTE
    echo ":: PASS: Discovery stateful substrates runtime-masked for restore"

# Retain a failed fresh-cluster init before retrying the pinned snapshot restore.
quarantine-discovery-openbao-throwaway:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      source=/var/lib/private/openbao
      retained=/var/lib/private/openbao-d5-throwaway
      if sudo test -d "$source" && sudo test ! -e "$retained"; then
        bytes=$(sudo du -sb /var/lib/private/openbao | awk '{print $1}')
        printf 'throwaway_bytes=%s state=%s\n' "$bytes" "$(systemctl is-active openbao.service 2>/dev/null || true)"
        test "$bytes" -lt 67108864
        export BAO_ADDR=http://127.0.0.1:8200
        ! BAO_TOKEN=$(sudo cat /run/secrets/vault_snapshot_token) \
          bao kv metadata get secret/shared/discord >/dev/null 2>&1
        sudo systemctl mask --runtime --now openbao.service
        sudo systemctl stop openbao.service || true
        sudo mv /var/lib/private/openbao "$retained"
      else
        sudo test -d "$retained"
        sudo test ! -e "$source"
        bytes=$(sudo du -sb "$retained" | awk '{print $1}')
      fi
      sudo install -d -m 0700 -o root -g root "$source"
      printf 'retained=%s bytes=%s\n' "$retained" "$bytes"
    REMOTE
    echo ":: PASS: failed throwaway OpenBao cluster retained; fresh state ready"

# Restore the pinned D4 OpenBao snapshot into a fresh node and prove metadata.
restore-discovery-openbao:
    #!/usr/bin/env bash
    set -euo pipefail
    RESTIC="$(nix eval --raw .#nixosConfigurations.discovery.pkgs.restic.outPath)/bin/restic"
    ssh -p 2222 erik@{{ip_discovery}} "RESTIC=$RESTIC bash -s" <<'REMOTE'
      set -euo pipefail
      snapshot=315ed0ea
      expected_sha256=8407ae773697c8511a6d2f2a24f0152dd547a91e7115148c8ecebea4f989ba29
      repository=/home/erik/vault/restic/openbao
      work=/var/lib/vault-snapshots/d5-restore-315ed0ea-v2
      sudo install -d -m 0700 -o root -g root "$work"
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      snap="$work/var/lib/vault-snapshots/openbao.snap"
      if ! sudo test -s "$snap"; then
        sudo env RESTIC_PASSWORD_FILE=/run/secrets/vault_restic_password \
          "$RESTIC" -r "$repository" restore "$snapshot" --target "$work"
      fi
      test "$(sudo sha256sum "$snap" | awk '{print $1}')" = "$expected_sha256"
      sudo chown -R erik:users "$work"
      chmod 0700 "$work"
      chmod 0600 "$snap"

      if ! ip link show br-openbao >/dev/null 2>&1; then
        sudo ip link add name br-openbao type bridge
      fi
      if ! ip -4 address show dev br-openbao | grep -Fq '172.31.82.1/29'; then
        sudo ip address add 172.31.82.1/29 dev br-openbao
      fi
      sudo ip link set br-openbao up
      sudo systemctl unmask --runtime openbao.service
      sudo systemctl reset-failed openbao.service
      if ! sudo systemctl start openbao.service; then
        sudo systemctl status openbao.service --no-pager -l || true
        sudo journalctl -u openbao.service -b --no-pager -n 100
        exit 1
      fi
      for _ in $(seq 1 60); do
        curl -sS -m 1 http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1 && break
        sleep 0.5
      done
      export BAO_ADDR=http://127.0.0.1:8200
      initialized=$(curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status |
        jq -r '.initialized')
      if test "$initialized" = false; then
        init_json=$(bao operator init -key-shares=1 -key-threshold=1 -format=json)
        throwaway_key=$(jq -r '.unseal_keys_b64[0]' <<<"$init_json")
        throwaway_token=$(jq -r '.root_token' <<<"$init_json")
        unset init_json
        bao operator unseal "$throwaway_key" >/dev/null
        BAO_TOKEN="$throwaway_token" bao operator raft snapshot restore -force "$snap"
        unset throwaway_key throwaway_token
      fi

      echo stage=seal-status
      sealed=$(curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status |
        jq -r '.sealed')
      if test "$sealed" = true; then
        unseal_key=$(sudo cat /run/secrets/vault_unseal_key)
        jq -n --arg key "$unseal_key" '{key: $key}' |
          curl -fsS -m 10 -X PUT --data @- http://127.0.0.1:8200/v1/sys/unseal >/dev/null
        unset unseal_key
      fi
      curl -fsS -m 10 http://127.0.0.1:8200/v1/sys/seal-status |
        jq -e '.initialized == true and .sealed == false' >/dev/null
      echo stage=approle-login
      role_id=$(sudo cat /run/secrets/vault_agent_role_id)
      secret_id=$(sudo cat /run/secrets/vault_agent_secret_id)
      login_json=$(jq -n --arg role_id "$role_id" --arg secret_id "$secret_id" \
        '{role_id: $role_id, secret_id: $secret_id}' |
        curl -fsS -m 10 -X POST --data @- http://127.0.0.1:8200/v1/auth/approle/login)
      unset role_id secret_id
      client_token=$(jq -er '.auth.client_token' <<<"$login_json")
      unset login_json
      echo stage=kv-proof
      BAO_TOKEN="$client_token" bao kv get -format=json secret/shared/discord |
        jq -e '.data.data | length > 0' >/dev/null
      unset client_token

      sudo systemctl unmask --runtime openbao-unseal.service openbao-unseal.timer vault-agent.service
      sudo systemctl start openbao-unseal.timer
      echo stage=vault-agent
      sudo systemctl start vault-agent.service
      for path in \
        /run/vault-agent/discord_webhook_incidents \
        /run/vault-agent/networking.env \
        /run/vault-agent/shared-db.env; do
        for _ in $(seq 1 100); do
          sudo test -s "$path" && break
          sleep 0.1
        done
        sudo test -s "$path"
      done
    REMOTE
    echo ":: PASS: OpenBao snapshot 315ed0ea restored, unsealed, and rendered"

# Restore the stopped Docker mirror, retaining the reinstall's fresh root.
restore-discovery-docker:
    #!/usr/bin/env bash
    set -euo pipefail
    evidence=.gsd/evidence/discovery-esp/manifest.json
    jq -e '
      .approval_ready == true
      and .backups.docker.cold_mirror == "/home/erik/vault/migration/discovery-docker-root"
      and .backups.docker.scratch_restore == "passed"
      and .backups.docker.metadata_sha256 == "a654304de8d8a29b1986b8ba9f2b3c19a87d58b58768b60c766d4e621ead42b5"
    ' "$evidence" >/dev/null
    evidence_sha=$(sha256sum "$evidence" | cut -d' ' -f1)
    ssh -p 2222 erik@{{ip_discovery}} "EVIDENCE_SHA=$evidence_sha bash -s" <<'REMOTE'
      set -euo pipefail
      source=/home/erik/vault/migration/discovery-docker-root
      marker=/home/erik/vault/migration/discovery-docker-root.final
      destination=/var/lib/docker
      retained=/var/lib/docker-d5-fresh
      echo stage=preflight
      vault_uuid=$(findmnt -nro UUID /home/erik/vault)
      marker_state=$(sudo test -s "$marker" && echo present || echo absent)
      source_state=$(sudo test -d "$source" && echo present || echo absent)
      printf 'vault_uuid=%s marker=%s source=%s docker=%s socket=%s\n' \
        "$vault_uuid" "$marker_state" "$source_state" \
        "$(systemctl is-active docker.service 2>/dev/null || true)" \
        "$(systemctl is-active docker.socket 2>/dev/null || true)"
      [[ "$EVIDENCE_SHA" =~ ^[0-9a-f]{64}$ ]]
      test "$vault_uuid" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      sudo test -d "$source"
      source_bytes=$(sudo du -xsb "$source" | awk '{print $1}')
      test "$source_bytes" -gt 10737418240
      test "$(sudo find "$source/containers" -name config.v2.json -print -quit)" != ""
      docker_units=(
        docker.service docker.socket docker-recover.service docker-recover.timer
      )
      hold_units=(docker.service docker.socket)
      for unit in "${hold_units[@]}"; do
        sudo install -d -m 0755 "/run/systemd/system/$unit.d"
        printf '%s\n' \
          '[Unit]' \
          'ConditionPathExists=/run/discovery-docker-restore-start-allowed' |
          sudo tee "/run/systemd/system/$unit.d/d5-restore.conf" >/dev/null
      done
      sudo systemctl daemon-reload
      sudo systemctl mask --runtime --now "${docker_units[@]}" || true
      sudo systemctl stop "${docker_units[@]}" || true
      sudo systemctl reset-failed "${docker_units[@]}" || true
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active docker.socket 2>/dev/null || true)" = inactive
      echo stage=retain
      if sudo test ! -e "$retained"; then
        fresh_bytes=$(sudo du -xsb "$destination" | awk '{print $1}')
        test "$fresh_bytes" -lt 1073741824
        sudo mv "$destination" "$retained"
      else
        sudo test -d "$retained"
      fi
      sudo install -d -m 0710 -o root -g docker "$destination"
      echo stage=rsync
      sudo rsync -aHAXx --numeric-ids --delete --stats "$source/" "$destination/"
      test "$(systemctl is-active docker.service 2>/dev/null || true)" = inactive
      test "$(systemctl is-active docker.socket 2>/dev/null || true)" = inactive
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete "$source/" "$destination/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      echo stage=manifest
      source_manifest=$(sudo find "$source" -xdev ! -type d -printf '%P\t%y\t%s\t%m\t%U\t%G\n' |
        LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      destination_manifest=$(sudo find "$destination" -xdev ! -type d -printf '%P\t%y\t%s\t%m\t%U\t%G\n' |
        LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      expected_manifest=$source_manifest
      test "$source_manifest" = "$expected_manifest"
      test "$destination_manifest" = "$expected_manifest"
      echo stage=start
      retained_hold=/run/discovery-docker-restore-hold
      sudo install -d -m 0700 "$retained_hold"
      for unit in "${hold_units[@]}"; do
        sudo mv "/run/systemd/system/$unit.d/d5-restore.conf" \
          "$retained_hold/$unit.$$.conf"
      done
      sudo systemctl daemon-reload
      sudo systemctl unmask --runtime docker.service docker.socket
      sudo systemctl reset-failed docker.service docker.socket
      sudo systemctl start docker.service || true
      for _ in $(seq 1 300); do
        systemctl is-active --quiet docker.service && break
        sleep 1
      done
      if ! systemctl is-active --quiet docker.service; then
        sudo systemctl status docker.service docker.socket --no-pager -l || true
        sudo journalctl -u docker.service -b --no-pager -n 100
        exit 1
      fi
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      printf 'containers=%s images=%s manifest_sha256=%s\n' \
        "$(sudo docker ps -aq | wc -l)" "$(sudo docker images -q | sort -u | wc -l)" \
        "$destination_manifest"
    REMOTE
    echo ":: PASS: Docker cold mirror restored exactly; fresh root retained"

# Resume Nix-owned stateful services after OpenBao and Docker restoration.
resume-discovery-postrestore-substrates:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      units=(
        docker-recover.service docker-recover.timer
        openbao-unseal.service openbao-unseal.timer
        libvirtd.service libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket
        haos-vm.service
      )
      sudo systemctl unmask --runtime "${units[@]}"
      sudo systemctl reset-failed "${units[@]}" harbor.service
      sudo systemctl start docker-recover.timer openbao-unseal.timer
      sudo systemctl start docker-recover.service
      sudo systemctl start libvirtd.service
      sudo systemctl restart harbor.service
      harbor_healthy=false
      for _ in $(seq 1 180); do
        if curl -fsS -m 3 http://127.0.0.1:8085/api/v2.0/health |
          jq -e '.status == "healthy"' >/dev/null 2>&1; then
          harbor_healthy=true
          break
        fi
        sleep 1
      done
      "$harbor_healthy"
      sudo systemctl start haos-vm.service
      haos_running=false
      for _ in $(seq 1 120); do
        if sudo virsh domstate haos | grep -Fx running >/dev/null 2>&1; then
          haos_running=true
          break
        fi
        sleep 1
      done
      "$haos_running"
      systemctl is-active docker.service libvirtd.service openbao.service \
        vault-agent.service harbor.service
      BAO_ADDR=http://127.0.0.1:8200 bao status | grep -Eq '^Sealed[[:space:]]+false$'
      sudo virsh domstate haos | grep -Fx running
    REMOTE
    echo ":: PASS: Docker recovery, unseal, Harbor, libvirt, and HAOS resumed"

# Encrypt Discovery home/SSH state to Kepler and hash-verify seven restore classes.
backup-discovery-home-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-home-restore-preflight
    DISCOVERY="{{ip_discovery}}"
    KEPLER="{{ip_kepler}}"
    samples=(
      "home/erik/.config/sops/age/keys.txt"
      "etc/ssh/ssh_host_ed25519_key"
      "home/erik/servarr/machines/discovery/.env.sops"
      "home/erik/servarr/machines/discovery/config/swag/nginx/proxy-confs/harbor.subdomain.conf"
      "home/erik/servarr/machines/discovery/config/swag/etc/letsencrypt/live/homelab.pastelariadev.com/priv-fullchain-bundle.pem"
      "home/erik/servarr/README.md"
      "home/erik/backup/Documents/erik/ha-agent/kaggle/out-qwen9b/gguf/model.safetensors-00002-of-00004.safetensors"
    )
    password_file=$(mktemp)
    hashes=$(mktemp)
    restore=$(mktemp -d)
    cleanup() {
      rm -f "$password_file" "$hashes"
      rm -rf "$restore"
    }
    trap cleanup EXIT
    ssh -p 2222 erik@"$DISCOVERY" \
      'sudo cat /run/secrets/vault_restic_password' >"$password_file"
    chmod 0600 "$password_file"
    export RESTIC_PASSWORD_FILE="$password_file"
    export RESTIC_REPOSITORY="sftp:erik@$KEPLER:/bulk/backups/discovery-esp-home"
    sftp_cmd="ssh -p 2222 -o BatchMode=yes erik@$KEPLER -s sftp"
    restic() {
      nix shell --builders "{{orion_builder}}" --builders-use-substitutes \
        --max-jobs 0 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
    }
    for sample in "${samples[@]}"; do
      ssh -p 2222 erik@"$DISCOVERY" \
        "sudo stat -c 'sample=%n bytes=%s' '/$sample' 2>/dev/null || echo 'missing=/$sample'" >&2
      ssh -p 2222 erik@"$DISCOVERY" "sudo test -s '/$sample'"
      ssh -p 2222 erik@"$DISCOVERY" "sudo sha256sum '/$sample'" >>"$hashes"
    done
    if ! restic snapshots >/dev/null 2>&1; then restic init; fi
    ssh -p 2222 erik@"$DISCOVERY" \
      'sudo tar --one-file-system -C / -cpf - home/erik etc/ssh' |
      restic backup --stdin --stdin-filename discovery-mutable-state.tar \
        --tag discovery-esp
    snapshot=$(restic snapshots --tag discovery-esp --latest 1 --json |
      jq -r 'max_by(.time).short_id')
    test -n "$snapshot" -a "$snapshot" != null
    restic dump "$snapshot" discovery-mutable-state.tar |
      tar -xpf - -C "$restore" "${samples[@]}"
    while read -r expected path; do
      relative=${path#/}
      actual=$(sha256sum "$restore/$relative" | awk '{print $1}')
      test "$actual" = "$expected" || {
        echo ":: BLOCKED: restore mismatch: $relative" >&2
        exit 1
      }
      printf 'verified=%s sha256=%s\n' "$relative" "$actual"
    done <"$hashes"
    printf 'snapshot=%s verified_at=%s\n' "$snapshot" "$(date --iso-8601=seconds)"
    echo ":: PASS: encrypted Discovery mutable-state snapshot and selective restore verified"

# Read-only live AdGuard identity/mount/capacity gate for isolated restore.
discovery-adguard-restore-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    source_bytes=$(ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      expected='adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927'
      inspect=$(sudo docker inspect adguard)
      jq -c '.[0] | {
        status: .State.Status,
        image: .Config.Image,
        mounts: [.Mounts[] | {type: .Type, name: .Name, source: .Source, destination: .Destination}]
      }' <<<"$inspect" >&2
      test "$(jq -r '.[0].State.Status' <<<"$inspect")" = running
      test "$(jq -r '.[0].Config.Image' <<<"$inspect")" = "$expected"
      work=$(jq -r '.[0].Mounts[] | select(.Destination == "/opt/adguardhome/work") | .Source' <<<"$inspect")
      config=$(jq -r '.[0].Mounts[] | select(.Destination == "/opt/adguardhome/conf") | .Source' <<<"$inspect")
      sudo test -d "$work"
      sudo test -d "$config"
      work_bytes=$(sudo du -xsb "$work" | cut -f1)
      config_bytes=$(sudo du -xsb "$config" | cut -f1)
      printf 'work=%s bytes=%s config=%s bytes=%s\n' \
        "$work" "$work_bytes" "$config" "$config_bytes" >&2
      jq -c '.[0] | {
        image: .Config.Image,
        mounts: [.Mounts[] | {type: .Type, source: .Source, destination: .Destination}],
        ports: .NetworkSettings.Ports
      }' <<<"$inspect" >&2
      printf '%s\n' "$((work_bytes + config_bytes))"
    REMOTE
    )
    [[ "$source_bytes" =~ ^[0-9]+$ ]]
    ssh -p 2222 erik@{{ip_orion}} "SOURCE_BYTES=$source_bytes bash -s" <<'REMOTE'
      set -euo pipefail
      available=$(findmnt -bnro AVAIL -T /projects)
      required=$((SOURCE_BYTES * 2))
      test "$available" -ge "$required"
      printf 'source_bytes=%s available=%s required=%s\n' \
        "$SOURCE_BYTES" "$available" "$required"
    REMOTE
    echo ":: PASS: live AdGuard state identified and Orion has restore capacity"

# Seed live AdGuard volume/config state onto Orion; stopped final sync follows.
discovery-adguard-restore-seed:
    #!/usr/bin/env bash
    set -euo pipefail
    just discovery-adguard-restore-preflight
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 {{ip_discovery}} >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    ssh -p 2222 erik@{{ip_orion}} "sudo HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/adguard
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      chmod 0644 "$known_hosts"
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      install -d -m 0700 "$root/work" "$root/conf"
      rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/var/lib/docker/volumes/discovery-adguard-work/_data/ "$root/work/"
      rsync -aHAXx --numeric-ids --delete --stats \
        --rsync-path='sudo rsync' -e "$remote_shell" \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/runtime/adguard/ "$root/conf/"
      du -xsb "$root/work" "$root/conf"
    REMOTE
    echo ":: PASS: online AdGuard restore seed complete; stopped final sync required"

# Stop only AdGuard and its exporter for the final delta, then restore both.
discovery-adguard-restore-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    discovery={{ip_discovery}}
    kepler={{ip_kepler}}
    evidence=.gsd/evidence/p3-dns/runs/20260715T235959Z-d5cf3b5979d8/result.json
    jq -e '.status == "passed"' "$evidence" >/dev/null
    for transport in +notcp +tcp; do
      test "$(dig "$transport" +short +time=3 +tries=1 @"$kepler" \
        discovery.homelab.pastelariadev.com A)" = "$discovery"
      test -n "$(dig "$transport" +short +time=3 +tries=1 @"$kepler" example.com A)"
    done
    inspect=$(ssh -p 2222 erik@"$discovery" \
      'sudo docker inspect adguard adguard-exporter')
    adguard_id=$(jq -r '.[] | select(.Name == "/adguard") | .Id' <<<"$inspect")
    exporter_id=$(jq -r '.[] | select(.Name == "/adguard-exporter") | .Id' <<<"$inspect")
    [[ "$adguard_id" =~ ^[0-9a-f]{64}$ && "$exporter_id" =~ ^[0-9a-f]{64}$ ]]
    test "$(jq -r '[.[].State.Running] | all' <<<"$inspect")" = true
    scan=$(mktemp)
    trap 'rm -f "$scan"' EXIT
    ssh-keyscan -p 2222 "$discovery" >"$scan" 2>/dev/null
    ssh-keygen -lf "$scan" -E sha256 |
      grep -Fq 'SHA256:Y+aJii1TUFtxSY7+LGT0hVBzEatKss/wDHBLFFXk0HE'
    hostkeys=$(base64 -w0 "$scan")
    stopped=1
    restart() {
      if test "$stopped" = 1; then
        ssh -p 2222 erik@"$discovery" \
          sudo docker start "$adguard_id" "$exporter_id" >/dev/null
        stopped=0
      fi
    }
    trap restart EXIT INT TERM
    started=$(date +%s)
    ssh -p 2222 erik@"$discovery" \
      sudo docker stop --time 120 "$exporter_id" "$adguard_id" >/dev/null
    ssh -p 2222 erik@{{ip_orion}} "sudo HOSTKEYS=$hostkeys bash -s" <<'REMOTE'
      set -euo pipefail
      root=/projects/recovery/discovery-esp/adguard
      test -d "$root/work" -a -d "$root/conf"
      known_hosts=$(mktemp)
      printf '%s' "$HOSTKEYS" | base64 -d >"$known_hosts"
      chmod 0644 "$known_hosts"
      trap 'rm -f "$known_hosts"' EXIT
      remote_shell="sudo -H -u erik ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts"
      sync() {
        rsync -aHAXx --numeric-ids --delete "$@" \
          --rsync-path='sudo rsync' -e "$remote_shell"
      }
      sync erik@{{ip_discovery}}:/var/lib/docker/volumes/discovery-adguard-work/_data/ "$root/work/"
      sync erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/runtime/adguard/ "$root/conf/"
      work_drift=$(sync --dry-run --itemize-changes \
        erik@{{ip_discovery}}:/var/lib/docker/volumes/discovery-adguard-work/_data/ "$root/work/")
      conf_drift=$(sync --dry-run --itemize-changes \
        erik@{{ip_discovery}}:/home/erik/servarr/machines/discovery/runtime/adguard/ "$root/conf/")
      test -z "$work_drift$conf_drift"
      du -xsb "$root/work" "$root/conf"
    REMOTE
    restart
    trap - EXIT INT TERM
    dns_ready=false
    for _ in $(seq 1 60); do
      running=$(ssh -p 2222 erik@"$discovery" \
        "sudo docker inspect '$adguard_id' '$exporter_id'" |
        jq -r '[.[].State.Running] | all')
      if test "$running" = true; then
        dns_ready=true
        for transport in +notcp +tcp; do
          test "$(dig "$transport" +short +time=3 +tries=1 @"$discovery" \
            discovery.homelab.pastelariadev.com A)" = "$discovery" ||
            dns_ready=false
          test -n "$(dig "$transport" +short +time=3 +tries=1 \
            @"$discovery" example.com A)" ||
            dns_ready=false
        done
        test "$dns_ready" = true && break
      fi
      sleep 1
    done
    test "$dns_ready" = true
    echo ":: PASS: stopped AdGuard final sync complete; downtime=$(( $(date +%s) - started ))s"

# Boot a disposable copy of AdGuard on Orion loopback and prove DNS behavior.
discovery-adguard-restore-drill:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_orion}} 'sudo bash -s' <<'REMOTE'
      set -euo pipefail
      image='adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927'
      root=/projects/recovery/discovery-esp/adguard
      source_work=/projects/recovery/discovery-esp/adguard/work
      source_conf=/projects/recovery/discovery-esp/adguard/conf
      run=$root/runs/$(date -u +%Y%m%dT%H%M%SZ)
      work=$run/work
      conf=$run/conf
      name=discovery-adguard-restore-drill
      command -v dig >/dev/null
      test -d "$source_work" -a -d "$source_conf"
      ! docker inspect "$name" >/dev/null 2>&1
      ! ss -H -lntu | grep -Eq '127\.0\.0\.1:(15353|18090)[[:space:]]'
      install -d -m 0700 "$work" "$conf"
      cp -a --reflink=auto "$source_work/." "$work/"
      cp -a --reflink=auto "$source_conf/." "$conf/"
      docker image inspect "$image" >/dev/null 2>&1 || docker pull "$image"
      created=false
      cleanup() {
        if "$created"; then
          docker stop --time 30 "$name" >/dev/null 2>&1 || true
        fi
      }
      trap cleanup EXIT INT TERM
      docker run --detach --rm --name "$name" \
        -p 127.0.0.1:15353:53/tcp \
        -p 127.0.0.1:15353:53/udp \
        -p 127.0.0.1:18090:80/tcp \
        -v "$work:/opt/adguardhome/work" \
        -v "$conf:/opt/adguardhome/conf" \
        "$image" >/dev/null
      created=true
      dns_ready=false
      for _ in $(seq 1 60); do
        if test "$(dig +notcp +short +time=2 +tries=1 -p 15353 \
          @127.0.0.1 restore-drill.homelab.pastelariadev.com A)" = \
          192.168.10.210; then
          dns_ready=true
          break
        fi
        sleep 1
      done
      test "$dns_ready" = true
      for transport in +notcp +tcp; do
        test "$(dig "$transport" +short +time=3 +tries=1 -p 15353 \
          @127.0.0.1 restore-drill.homelab.pastelariadev.com A)" = \
          192.168.10.210
        test -n "$(dig "$transport" +short +time=3 +tries=1 -p 15353 \
          @127.0.0.1 example.com A)"
        test "$(dig "$transport" +short +time=3 +tries=1 -p 15353 \
          @127.0.0.1 restore-drill.doubleclick.net A)" = 0.0.0.0
        dig "$transport" +dnssec +time=3 +tries=1 -p 15353 \
          @127.0.0.1 cloudflare.com A |
          grep -Eq 'flags:.* ad[;[:space:]]'
      done
      curl --fail --silent --show-error --max-time 3 \
        -o /dev/null http://127.0.0.1:18090/
      docker inspect "$name" |
        jq -c '.[0] | {
          image: .Image,
          running: .State.Running,
          ports: .NetworkSettings.Ports,
          mounts: [.Mounts[] | {source: .Source, destination: .Destination}]
        }' | tee "$run/result.json"
      test "$(jq -r .running "$run/result.json")" = true
      echo ":: PASS: isolated AdGuard restore resolves fleet/external/filter/DNSSEC over UDP+TCP"
    REMOTE

# Maintenance-window finalization. This recipe never stops Docker itself: the
# caller must quiesce dependent writers in the reviewed order first. It refuses
# to copy while Docker is active and proves a second dry-run has zero changes.
discovery-docker-mirror-finalize:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      source=/var/lib/docker
      destination=/home/erik/vault/migration/discovery-docker-root
      marker=/home/erik/vault/migration/discovery-docker-root.final
      test "$(systemctl is-active docker 2>/dev/null || true)" = inactive || {
        echo ":: BLOCKED: Docker must already be inactive" >&2
        exit 1
      }
      primary_root=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105-part2)
      vault_part=$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M-part1)
      test "$(findmnt -nro SOURCE -T "$source" | sed "s/\\[.*//")" = "$primary_root"
      test "$(findmnt -nro SOURCE -T "$destination")" = "$vault_part"
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test -d "$destination"
      sudo rsync -aHAXx --numeric-ids --delete "$source/" "$destination/"
      drift=$(sudo rsync -aHAXxni --numeric-ids --delete "$source/" "$destination/")
      test -z "$drift" || { printf '%s\n' "$drift" >&2; exit 1; }
      source_bytes=$(sudo du -xsb "$source" | awk '{print $1}')
      mirror_bytes=$(sudo du -xsb "$destination" | awk '{print $1}')
      source_manifest=$(sudo find "$source" -xdev -printf '%P\t%y\t%s\t%m\t%U\t%G\n' | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      mirror_manifest=$(sudo find "$destination" -xdev -printf '%P\t%y\t%s\t%m\t%U\t%G\n' | LC_ALL=C sort | sha256sum | cut -d' ' -f1)
      test "$source_manifest" = "$mirror_manifest"
      printf 'finalized_at=%s\nsource_bytes=%s\nmirror_bytes=%s\nmanifest_sha256=%s\n' \
        "$(date --iso-8601=seconds)" "$source_bytes" "$mirror_bytes" "$source_manifest" \
        | sudo tee "$marker" >/dev/null
      sudo chmod 0600 "$marker"
      sudo cat "$marker"
    REMOTE
    echo ":: PASS: stopped Docker mirror is exact and restore-ready"

# Read-only post-install acceptance gate. Run only after dependency-ordered
# restoration has completed; it does not start or repair any service.
diagnose-discovery-gpu:
    #!/usr/bin/env bash
    set -euo pipefail
    pciutils="$(nix eval --raw .#nixosConfigurations.discovery.pkgs.pciutils.outPath)"
    ssh -p 2222 erik@{{ip_discovery}} "TOOLS_PATH=$pciutils/bin bash -s" <<'REMOTE'
      export PATH="$TOOLS_PATH:$PATH"
      echo ":: pci"
      lspci -nnk | grep -A3 -Ei 'VGA|3D|NVIDIA' || true
      echo ":: modules"
      lsmod | grep -E '^nvidia' || true
      echo ":: devices"
      for device in /dev/nvidia*; do
        test ! -e "$device" || stat -c '%n %a %U:%G' "$device"
      done
      echo ":: nvidia-smi"
      nvidia-smi || true
      echo ":: units"
      systemctl status nvidia-persistenced.service \
        nvidia-container-toolkit-cdi-generator.service --no-pager -l || true
      echo ":: kernel"
      journalctl -b -k --no-pager |
        grep -Ei 'nvidia|nouveau|NVRM|BAR|IOMMU|firmware' | tail -120 || true
    REMOTE

# Run one bounded 4K60 NVENC load and sample fan/thermal telemetry.
test-discovery-gpu-load duration="60":
    #!/usr/bin/env bash
    set -euo pipefail
    duration={{duration}}
    test "$duration" -ge 5
    test "$duration" -le 900
    ssh -p 2222 erik@{{ip_discovery}} "DURATION=$duration bash -s" <<'REMOTE'
      set -euo pipefail
      duration=$DURATION
      query() {
        nvidia-smi --query-gpu=timestamp,fan.speed,temperature.gpu,power.draw,utilization.gpu,utilization.encoder \
          --format=csv,noheader
      }
      image=lscr.io/linuxserver/jellyfin:10.11.11@sha256:bb8d372e35d5c4a6cb61d830a06f5b5846528315b97cf5d38b80eea1e430efa7
      sudo docker inspect -f '{{"{{"}}.State.Health.Status{{"}}"}}' jellyfin | grep -Fx healthy
      sudo docker image inspect "$image" >/dev/null
      query
      timeout "$((duration + 20))" sudo docker run --rm --pull never \
        --network none --device nvidia.com/gpu=all \
        --entrypoint /usr/lib/jellyfin-ffmpeg/ffmpeg "$image" \
        -hide_banner -loglevel error -re \
        -f lavfi -i testsrc2=size=3840x2160:rate=60 -t "$duration" \
        -c:v h264_nvenc -preset p1 -f null - &
      load_pid=$!
      for _ in $(seq 1 "$((duration / 2 + 2))"); do
        query
        kill -0 "$load_pid" 2>/dev/null || break
        sleep 2
      done
      wait "$load_pid"
      query
    REMOTE

# Temporarily request a fixed GPU fan speed through a private headless X server.
test-discovery-gpu-fan percent="80" duration="10":
    #!/usr/bin/env bash
    set -euo pipefail
    percent={{percent}}
    duration={{duration}}
    test "$percent" -ge 30
    test "$percent" -le 100
    test "$duration" -ge 5
    test "$duration" -le 30
    xorg=$(nix eval --raw .#nixosConfigurations.discovery.pkgs.xorg.xorgserver.outPath)
    settings=$(nix eval --raw .#nixosConfigurations.discovery.config.hardware.nvidia.package.settings.outPath)
    driver=$(nix eval --raw .#nixosConfigurations.discovery.config.hardware.nvidia.package.bin.outPath)
    nix-store --realise "$xorg" "$settings" "$driver" >/dev/null
    nix copy --to ssh-ng://erik@{{ip_discovery}}:2222 "$xorg" "$settings" "$driver"
    ssh -p 2222 erik@{{ip_discovery}} \
      "sudo bash -s -- $xorg $settings $driver $percent $duration" <<'REMOTE'
      set -euo pipefail
      xorg=$1
      settings=$2
      driver=$3
      percent=$4
      duration=$5
      work=$(mktemp -d /run/discovery-gpu-fan-test.XXXXXX)
      printf '%s\n' \
        'Section "Files"' \
        "  ModulePath \"$driver/lib/xorg/modules\"" \
        "  ModulePath \"$xorg/lib/xorg/modules\"" \
        'EndSection' \
        'Section "Device"' \
        '  Identifier "GPU0"' \
        '  Driver "nvidia"' \
        '  BusID "PCI:1:0:0"' \
        '  Option "Coolbits" "4"' \
        '  Option "AllowEmptyInitialConfiguration" "True"' \
        'EndSection' \
        'Section "Screen"' \
        '  Identifier "Screen0"' \
        '  Device "GPU0"' \
        'EndSection' >"$work/xorg.conf"
      "$xorg/bin/Xorg" :99 -config "$work/xorg.conf" -noreset -nolisten tcp \
        -logfile "$work/Xorg.log" >"$work/stdout.log" 2>&1 &
      xpid=$!
      cleanup() {
        "$settings/bin/nvidia-settings" -c :99 \
          -a '[gpu:0]/GPUFanControlState=0' || true
        kill "$xpid" 2>/dev/null || true
        wait "$xpid" 2>/dev/null || true
      }
      trap cleanup EXIT
      for _ in $(seq 1 10); do
        "$settings/bin/nvidia-settings" -c :99 -q gpus >/dev/null 2>&1 && break
        kill -0 "$xpid" 2>/dev/null || {
          cat "$work/Xorg.log"
          exit 1
        }
        sleep 1
      done
      "$settings/bin/nvidia-settings" -c :99 -q gpus >/dev/null
      nvidia-smi --query-gpu=fan.speed,temperature.gpu,power.draw --format=csv,noheader
      "$settings/bin/nvidia-settings" -c :99 \
        -a '[gpu:0]/GPUFanControlState=1' \
        -a "[fan:0]/GPUTargetFanSpeed=$percent"
      sleep "$duration"
      "$settings/bin/nvidia-settings" -c :99 \
        -q '[fan:0]/GPUCurrentFanSpeed' \
        -q '[fan:0]/GPUTargetFanSpeed'
      nvidia-smi --query-gpu=fan.speed,temperature.gpu,power.draw --format=csv,noheader
    REMOTE

# Read-only post-install acceptance gate. Run only after dependency-ordered
# restoration has completed; it does not start or repair any service.
verify-discovery-esp:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@{{ip_discovery}} 'bash -s' <<'REMOTE'
      set -euo pipefail
      esp_bytes=$(findmnt -bnro SIZE /boot)
      test "$esp_bytes" -ge 2000000000
      test "$(findmnt -nro FSTYPE /boot)" = vfat
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      sudo btrfs filesystem usage -b / | grep -Eq '^Data,RAID1:'
      sudo btrfs filesystem usage -b / | grep -Eq '^Metadata,RAID1:'
      sudo systemctl is-active sshd tailscaled docker libvirtd openbao vault-agent openbao-unseal.timer
      test "$(systemctl show -p Result --value openbao-unseal.service)" = success
      echo stage=openbao
      BAO_ADDR=http://127.0.0.1:8200 bao status | grep -Eq '^Sealed[[:space:]]+false$'
      echo stage=dns
      dig +short +time=3 +tries=1 @{{ip_discovery}} discovery.homelab.pastelariadev.com A | grep -Eq '^[0-9]+(\.[0-9]+){3}$'
      echo stage=grafana
      curl -kfsS -o /dev/null https://grafana.homelab.pastelariadev.com/
      echo stage=haos
      sudo virsh domstate haos | grep -Fx running
      echo stage=failed-units
      failed=$(systemctl --failed --no-legend | awk 'NF')
      printf '%s' "$failed"
      test -z "$failed"
      printf 'generation='; readlink -f /run/current-system
      printf 'esp_bytes=%s\n' "$esp_bytes"
      sudo docker ps --format '{{"{{"}}.Names{{"}}"}}\t{{"{{"}}.Status{{"}}"}}' | sort
    REMOTE
    echo ":: PASS: Discovery post-install critical acceptance gate"

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

# Send non-firing previews of the Discord incident and deploy formats. Webhook
# values stay on Discovery; output contains only HTTP status codes.
send-discord-samples:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="$(just _host-ip discovery)"
    ssh -p 2222 erik@"$IP" 'bash -s' <<'REMOTE'
      set -euo pipefail
      send() {
        local secret=$1 payload=$2
        webhook=$(sudo -n cat "$secret")
        status=$(curl -sS -o /dev/null -w "%{http_code}" \
          -H "Content-Type: application/json" --data "$payload" "$webhook")
        test "$status" = 204
        printf "%s: HTTP %s\n" "$(basename "$secret")" "$status"
      }
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      incident=$(jq -cn --arg now "$now" '{
        allowed_mentions:{parse:[]},
        embeds:[{
          title:"[TEST] FIRING (1) · ArgusMessagePreview",
          description:"**FIRING · WARNING**\nSample only — no incident occurred.\n**Instance:** `discovery`\n**Job:** `preview`\nShows evidence, ownership, and useful actions.\n**Value:** `probe=1`\n[Dashboard](http://grafana:3000/) · [Rule](http://grafana:3000/alerting/list) · [Silence](http://grafana:3000/alerting/silences/new)",
          color:16705372,
          timestamp:$now
        }]
      }')
      deploy=$(jq -cn --arg now "$now" '{
        allowed_mentions:{parse:[]},
        embeds:[{
          title:"[TEST] Kindle release succeeded",
          description:"Sample only — no deployment occurred.\n**Version:** `v1.2.3`\n**Commit:** [`abcdef0`](https://github.com/ErikBPF/kindle-dash/commit/abcdef0000000000000000000000000000000000)\n**Image:** `sha256:0123456789ab…`",
          color:5763719,
          timestamp:$now
        }]
      }')
      send /run/vault-agent/kindle-release-discord-incidents "$incident"
      send /run/vault-agent/kindle-release-discord-deploys "$deploy"
    REMOTE

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
