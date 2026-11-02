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

# Compatibility entrypoint: Endeavour now participates in the Orion check batch.
check-endeavour-remote target="endeavour" ref="HEAD":
    just check-remote {{quote(ref)}}

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

# Stream Pathfinder's full home as one tar object into an encrypted restic repo
# on Kepler, then restore and hash one representative file. No plaintext archive
# lands on either workstation. Passphrase is read silently and never logged.
pathfinder-home-samples:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -p 2222 erik@"{{ip_pathfinder}}" \
      'find /home/erik/Documents /home/erik/Downloads -xdev -type f -size +0c -printf "%p\n" 2>/dev/null | sed "s|^/home/erik/||" | head -20'

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
    export NIX_CONFIG="builders = $(just _builders pathfinder)
    max-jobs = 1
    builders-use-substitutes = true"
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
    export NIX_CONFIG="builders = $(just _builders endeavour)
    max-jobs = 1
    builders-use-substitutes = true"
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

# voyager is the 1 GB x86 Oracle micro: it can't compile, so build on Orion and
# substitute/activate on the target. First run after `just infect-voyager` the
# base NixOS is root@22 → `just switch-voyager root 22`; the flake config then
# moves SSH to erik@2222 → steady state `just switch-voyager`. Stages the sops
# age key so sops-nix can decrypt tailscale_authkey + the compose .env.sops.
switch-voyager user="erik" port="2222":
    #!/usr/bin/env bash
    set -euo pipefail
    BUILDERS="$(just _builders voyager)"
    if [[ "{{user}}:{{port}}" == "root:22" ]]; then IP="{{ip_voyager}}"; else IP="{{tailscale_voyager}}"; fi
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'sudo mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/tmp/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" \
        'sudo mv /tmp/age-keys.txt /var/lib/sops-staging/age-keys.txt && sudo chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#voyager \
        --target-host {{user}}@"$IP" \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true \
        --max-jobs 1 \
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
        --max-jobs 1 \
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
    BUILDERS="$(just _builders vanguard)"
    if [[ "{{user}}:{{port}}" == "root:22" ]]; then IP="{{ip_vanguard}}"; else IP="{{tailscale_vanguard}}"; fi
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'sudo mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/tmp/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" \
        'sudo mv /tmp/age-keys.txt /var/lib/sops-staging/age-keys.txt && sudo chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#vanguard \
        --target-host {{user}}@"$IP" \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true \
        --max-jobs 1 \
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
    BUILDERS="$(just _builders vanguard)"
    IP="{{ip_vanguard}}"
    ssh -p {{port}} -o StrictHostKeyChecking=accept-new {{user}}@"$IP" 'mkdir -p /var/lib/sops-staging'
    scp -P {{port}} ~/.config/sops/age/keys.txt {{user}}@"$IP":/var/lib/sops-staging/age-keys.txt
    ssh -p {{port}} {{user}}@"$IP" 'chmod 600 /var/lib/sops-staging/age-keys.txt'
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild boot --flake .#vanguard \
        --target-host {{user}}@"$IP" \
        --option builders "$BUILDERS" \
        --option builders-use-substitutes true \
        --max-jobs 1 \
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

diagnose-pathfinder-bootstrap:
    ssh -p 2222 erik@$(jq -r '.hosts.pathfinder.tailscaleIp // .hosts.pathfinder.ip' fleet.json) "sudo systemctl status sops-first-boot home-manager-erik tailscaled-autoconnect --no-pager -l; echo ':: btrfs scrub'; sudo systemctl status btrfs-scrub--.timer btrfs-scrub--.service --no-pager -l || true; sudo systemctl cat btrfs-scrub--.timer; sudo journalctl -u btrfs-scrub--.timer -u btrfs-scrub--.service -b --no-pager -n 40; echo ':: account'; sudo passwd -S erik; echo ':: home path'; namei -l /home/erik/Documents/erik; echo ':: home-manager log'; sudo journalctl -u home-manager-erik -b --no-pager -n 80; echo ':: staging'; sudo find /var/lib/sops-staging -maxdepth 1 -type f -printf '%f %m %u:%g\n'; echo ':: age destination'; find ~/.config/sops/age -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null || true"

recover-pathfinder-scrub:
    ssh -p 2222 erik@$(jq -r '.hosts.pathfinder.tailscaleIp // .hosts.pathfinder.ip' fleet.json) "sudo systemctl reset-failed btrfs-scrub--.timer; sudo systemctl start btrfs-scrub--.timer; systemctl is-active btrfs-scrub--.timer"

diagnose-pathfinder-login:
    ssh -p 2222 erik@{{ip_pathfinder}} "echo ':: account'; sudo passwd -S erik; echo ':: sddm'; sudo systemctl status display-manager --no-pager -l; echo ':: authentication log'; sudo journalctl -b --no-pager -n 150 -u display-manager -t sddm-helper -t unix_chkpwd -t systemd-logind"

# Workstations remain user-owned tailnet nodes; the fleet OAuth secret is
# intentionally scoped to tag:server and cannot enroll Pathfinder after a wipe.
pathfinder-tailscale-login:
    ssh -t -p 2222 erik@{{ip_pathfinder}} "sudo tailscale up --hostname=pathfinder --accept-dns=true --accept-routes && sudo systemctl reset-failed tailscaled-autoconnect.service && sudo systemctl start tailscaled-autoconnect.service"

# Build a bootable SD image (aarch64) on orion. target=archinaut (production) or
# archinaut-base (rescue / kernel-direct prototype — flash a SPARE card, boot
# with the printer ON to prove no-u-boot boot, RFC 2026-06-20).
build-archinaut-sd target="archinaut":
    # Only Orion provides aarch64 binfmt capacity; reuse its canonical SSH spec.
    nix build .#nixosConfigurations.{{target}}.config.system.build.sdImage \
        --builders '{{orion_builder}}' --builders-use-substitutes \
        --max-jobs 1 --show-trace --out-link result-{{target}}-sd
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
    max-jobs = 1
    builders-use-substitutes = true"
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#telstar \
        --extra-files /tmp/nixos-extra-telstar \
        --show-trace \
        ubuntu@{{ip_telstar}}

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
