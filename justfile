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
    check_map=$(nix eval --json .#checks \
      --apply "systems: builtins.mapAttrs (_: checks: builtins.attrNames checks) systems")
    printf %s "$check_map" | jq -e \
      "any(.[]?[]; . == \"configurations:nixos:endeavour\")" >/dev/null
    mapfile -t installables < <(printf %s "$check_map" | jq -r \
      "to_entries[] as \$system | \$system.value[] |
        select(. != "configurations:nixos:endeavour") |
        \".#checks.\\(\$system.key).\\(. | @json)\"")
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
# laptop is Tailscale only (roaming), use: just deploy laptop <tailscale-ip> 2222

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

switch-pathfinder:
    just deploy-rs pathfinder

# Read-only evidence gate for Pathfinder's approved 512M -> 2G ESP migration.
# Conservative projection keeps the largest installed kernel + initrd as the
# known-good pair, adds the candidate pair, then requires 25% ESP reserve.
pathfinder-esp-preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    IP="{{ip_pathfinder}}"
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
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r '.[0].short_id')
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
      sudo systemctl is-active sshd tailscaled syncthing nfs-server
      systemctl --user is-active podman-compose-ai-serving.service podman-compose-docs-search.service
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
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r '.[0].short_id')
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
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r '.[0].short_id')
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
    ssh -p 2222 erik@"$PATHFINDER" "sudo tar --one-file-system -C /home/erik -cpf - ." \
      | restic backup --stdin --stdin-filename pathfinder-home.tar --tag esp-migration
    snapshot=$(restic snapshots --tag esp-migration --latest 1 --json | jq -r '.[0].short_id')
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
    BUILDERS="$(just _builders {{target}})"; \
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-substitutes --sudo --show-trace \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true \
        --max-jobs 0

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
    ssh -p 2222 erik@{{ip_pathfinder}} "sudo systemctl status sops-first-boot home-manager-erik tailscaled-autoconnect --no-pager -l; echo ':: account'; sudo passwd -S erik; echo ':: home path'; namei -l /home/erik/Documents/erik; echo ':: home-manager log'; sudo journalctl -u home-manager-erik -b --no-pager -n 80; echo ':: staging'; sudo find /var/lib/sops-staging -maxdepth 1 -type f -printf '%f %m %u:%g\n'; echo ':: age destination'; find ~/.config/sops/age -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null || true"

diagnose-orion-bootstrap:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl status sops-first-boot home-manager-erik tailscaled-autoconnect --no-pager -l; echo ':: account'; sudo passwd -S erik; echo ':: home top-level'; find /home/erik -mindepth 1 -maxdepth 1 -printf '%f %y %u:%g\n' | sort; echo ':: ssh ownership'; namei -l /home/erik/.ssh/config; ls -la /home/erik/.ssh; echo ':: sops first-boot log'; sudo journalctl -u sops-first-boot -b --no-pager -n 100; echo ':: home-manager log'; sudo journalctl -u home-manager-erik -b --no-pager -n 100; echo ':: tailscale log'; sudo journalctl -u tailscaled-autoconnect -b --no-pager -n 100; echo ':: staging'; sudo find /var/lib/sops-staging -maxdepth 1 -type f -printf '%f %m %u:%g\n'; echo ':: age destination'; find ~/.config/sops/age -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null || true"

recover-orion-bootstrap:
    ssh -p 2222 erik@{{ip_orion}} "chmod u+w ~/.ssh/config; sudo systemctl reset-failed home-manager-erik tailscaled-autoconnect sops-first-boot; sudo systemctl start home-manager-erik; sudo systemctl start tailscaled-autoconnect; sudo systemctl reset-failed sops-first-boot"

recover-orion-nfs:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl reset-failed mnt-nfs-fast.mount mnt-nfs-bulk.mount; sudo systemctl restart mnt-nfs-fast.automount mnt-nfs-bulk.automount; timeout 15 ls -d /mnt/nfs/fast /mnt/nfs/bulk >/dev/null"

diagnose-orion-nfs:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl status mnt-nfs-fast.mount mnt-nfs-bulk.mount mnt-nfs-fast.automount mnt-nfs-bulk.automount --no-pager -l; sudo journalctl -b -u mnt-nfs-fast.mount -u mnt-nfs-bulk.mount --no-pager -n 100; echo ':: tailscale peers'; tailscale status; echo ':: tailscale dns'; tailscale dns status; echo ':: resolve kepler'; getent ahosts kepler || true; resolvectl query kepler || true; echo ':: nfs filesystems'; grep nfs /proc/filesystems || true; echo ':: modules'; lsmod | grep -E '(^nfs|sunrpc|lockd)' || true"

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
    ssh -p 2222 erik@"$IP" 'uid=$(id -u); sudo systemctl start user-runtime-dir@$uid.service user@$uid.service; export XDG_RUNTIME_DIR=/run/user/$uid; systemctl --user daemon-reload && systemctl --user restart servarr-pull.service'
    ssh -p 2222 erik@"$IP" 'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user status servarr-pull.service --no-pager -n15'
    echo ":: {{target}} now on origin/{{branch}}. Recreate changed stacks: just kick-stack {{target}} <stack>"

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

# Permanently remove the seven disposable AI containers, their seven exact
# images, and /fast/ai-models. The helper re-inventories and fails closed.
kepler-retire-ai-serving-user-approved:
    ssh -p 2222 erik@{{ip_kepler}} 'tool=$(command -v kepler-collision-recovery-inventory); interpreter=$(head -n1 "$tool"); interpreter=${interpreter#\#!}; exec "$interpreter" - --execute-user-approved' < modules/hosts/kepler/_retire_ai_serving.py

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
    response=$(curl --fail --silent --show-error --get http://discovery:9090/api/v1/query \
      --data-urlencode 'query=up{job="etcd"}')
    printf '%s\n' "$response" | jq -c '.data.result[]? | {instance: .metric.instance, value: .value[1]}'
    test "$(printf '%s\n' "$response" | jq '[.data.result[]? | select(.value[1] == "1")] | length')" -eq 3

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
    ssh -p 2222 erik@{{ip_kepler}} "sudo systemctl list-jobs --no-pager; sudo systemctl status microvms.target k3s-bootstrap-materialize.service microvm@cp-{1,2,3}.service --no-pager -l; sudo journalctl -b -u k3s-bootstrap-materialize.service -u microvm@cp-1.service -u install-microvm-cp-1.service --no-pager -n 120; sudo find -L /run/secrets -maxdepth 2 -printf 'secret-path %P %y\n'; sudo find /run/k3s-bootstrap -maxdepth 1 -type f -printf 'host %f %s bytes\n'; ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null root@10.250.0.11 'find /run/k3s-bootstrap -maxdepth 1 -type f -printf \"guest %f %s bytes\\n\"; systemctl status k3s-bootstrap-secrets.service k3s-bootstrap-secrets.timer --no-pager -l; journalctl -b -u k3s-bootstrap-secrets.service --no-pager -n 80'"

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
    kubectl --context pastelariadev -n argocd get secret homelab-gitops-repo \
      -o jsonpath='{.data.sshPrivateKey}' \
      | base64 --decode \
      | jq -Rs . \
      | sops set --value-stdin secrets/sops/secrets.yaml '["k3s_bootstrap"]["argocd_repo_ssh_key"]'
    echo ":: k3s bootstrap credentials encrypted in sops"

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
    test "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest_sha256"])' "{{authorization}}")" = "$hash" || {
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
      mirror=$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098)
      vault=$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M)
      test "$primary" = /dev/sda
      test "$mirror" = /dev/sdc
      test "$vault" = /dev/sdb
      test "$(findmnt -nro SOURCE /boot)" = /dev/sda1
      test "$(findmnt -nro SOURCE /)" = "/dev/sda2[/root]"
      test "$(findmnt -nro UUID /home/erik/vault)" = d026033d-158d-49ca-9ff9-dd2d5c8a21dc
      test "$(sudo docker info --format '{{"{{"}}.DockerRootDir{{"}}"}}')" = /var/lib/docker
      test "$(findmnt -nro SOURCE -T /var/lib/docker)" = "/dev/sda2[/root]"
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
      test "$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000105)" = /dev/sda
      test "$(readlink -f /dev/disk/by-id/ata-KINGSTON_SA400S37480G_AA000000000000000098)" = /dev/sdc
      test "$(readlink -f /dev/disk/by-id/ata-ST4000DM004-2CV104_ZTT25R4M)" = /dev/sdb
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
      sudo systemctl is-active sshd tailscaled docker libvirtd openbao openbao-unseal vault-agent
      BAO_ADDR=http://127.0.0.1:8200 bao status | grep -Eq '^Sealed[[:space:]]+false$'
      dig +short +time=3 +tries=1 @127.0.0.1 discovery.homelab.pastelariadev.com A | grep -Eq '^[0-9]+(\.[0-9]+){3}$'
      curl -kfsS -o /dev/null https://grafana.homelab.pastelariadev.com/
      sudo virsh domstate haos | grep -Fx running
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

add-ampagent:
    #!/usr/bin/env bash
    set -euo pipefail
    deb=$(find . -maxdepth 1 -name 'ampagent-*kace.nstech.com.br*.deb' ! -name '* copy*' -print -quit)
    if [ -z "$deb" ]; then
        echo "ERROR: No ampagent .deb found in project root"
        echo "  Drop the original .deb (with token in filename) here and retry"
        exit 1
    fi
    echo ":: Found token-bearing KACE package"

    # Extract enrollment token from filename (part after '+' before '.deb')
    token=$(basename "$deb" | sed -n 's/.*\.com\.br+\(.*\)\.deb/\1/p')
    if [ -z "$token" ]; then
        echo "ERROR: Could not extract token from filename"
        exit 1
    fi
    echo ":: Extracted enrollment token"

    # Add a clean-named temporary copy to the Nix store. Never print the
    # original token-bearing filename and always remove the temporary copy.
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cp "$deb" "$tmp/ampagent-15.0.54.deb"
    nix-store --add-fixed sha256 "$tmp/ampagent-15.0.54.deb" >/dev/null
    echo ":: Added .deb to nix store"

    # Upsert kace_token in sops secrets
    nix run nixpkgs#sops -- set secrets/sops/secrets.yaml '["kace_token"]' "\"$token\""
    echo ":: Updated kace_token in sops"

    echo ":: Done. Original token-bearing package remains gitignored at repo root"

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
