switch-orion:
    just deploy-rs orion

recache-orion:
    ssh -p 2222 erik@{{ip_orion}} 'sudo systemctl start nix-cache-builder.service'

stop-recache-orion:
    ssh -p 2222 erik@{{ip_orion}} 'sudo systemctl stop nix-cache-builder.service'

reboot-orion:
    ssh -p 2222 erik@{{ip_orion}} 'sudo systemctl reboot'

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

orion-esp-graph-proof:
    #!/usr/bin/env bash
    set -euo pipefail
    BUILDERS="$(just _builders orion)"
    script=$(nix build --no-link --print-out-paths \
      .#nixosConfigurations.orion-esp-installer.config.system.build.diskoScript \
      --builders "$BUILDERS" --builders-use-substitutes --max-jobs 1 | tail -1)
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
    export NIX_CONFIG="builders = {{apollo_builder}}
    max-jobs = 1
    builders-use-substitutes = true"
    just orion-esp-live-preflight
    just orion-esp-graph-proof
    nix build --no-link \
      .#nixosConfigurations.orion-esp-installer.config.system.build.toplevel \
      --builders "{{apollo_builder}}" \
      --builders-use-substitutes --max-jobs 1 --show-trace
    extra=$(mktemp -d)
    trap 'rm -rf "$extra"' EXIT
    mkdir -p "$extra/var/lib/sops-staging"
    cp ~/.config/sops/age/keys.txt "$extra/var/lib/sops-staging/age-keys.txt"
    chmod 600 "$extra/var/lib/sops-staging/age-keys.txt"
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

# Save a read-only display snapshot locally; repeat while Orion is black, before reboot.
capture-orion-display:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    capture_dir=$(mktemp -d /tmp/orion-display-XXXXXXXX)
    echo "Display capture: $capture_dir/snapshot.txt"
    timeout -k 5s 180s ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 erik@{{ip_orion}} 'bash -s' < scripts/capture-orion-display.sh > "$capture_dir/snapshot.txt" 2>&1 || { echo "Capture incomplete; retained partial output in $capture_dir/snapshot.txt" >&2; exit 1; }
    if grep -q '^CAPTURE_FAILED status=' "$capture_dir/snapshot.txt"; then
        echo "Partial capture: inspect CAPTURE_FAILED markers."
    fi

diagnose-orion-bootstrap:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl status sops-first-boot home-manager-erik tailscaled-autoconnect --no-pager -l; echo ':: account'; sudo passwd -S erik; echo ':: home top-level'; find /home/erik -mindepth 1 -maxdepth 1 -printf '%f %y %u:%g\n' | sort; echo ':: ssh ownership'; namei -l /home/erik/.ssh/config; ls -la /home/erik/.ssh; echo ':: sops first-boot log'; sudo journalctl -u sops-first-boot -b --no-pager -n 100; echo ':: home-manager log'; sudo journalctl -u home-manager-erik -b --no-pager -n 100; echo ':: tailscale log'; sudo journalctl -u tailscaled-autoconnect -b --no-pager -n 100; echo ':: staging'; sudo find /var/lib/sops-staging -maxdepth 1 -type f -printf '%f %m %u:%g\n'; echo ':: age destination'; find ~/.config/sops/age -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null || true"

recover-orion-bootstrap:
    ssh -p 2222 erik@{{ip_orion}} "chmod u+w ~/.ssh/config; sudo systemctl reset-failed home-manager-erik tailscaled-autoconnect sops-first-boot; sudo systemctl start home-manager-erik; sudo systemctl start tailscaled-autoconnect; sudo systemctl reset-failed sops-first-boot"

recover-orion-nfs:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl reset-failed mnt-nfs-fast.mount mnt-nfs-bulk.mount; sudo systemctl restart mnt-nfs-fast.automount mnt-nfs-bulk.automount; timeout 15 ls -d /mnt/nfs/fast /mnt/nfs/bulk >/dev/null"

diagnose-orion-nfs:
    ssh -p 2222 erik@{{ip_orion}} "sudo systemctl status mnt-nfs-fast.mount mnt-nfs-bulk.mount mnt-nfs-fast.automount mnt-nfs-bulk.automount --no-pager -l; sudo journalctl -b -u mnt-nfs-fast.mount -u mnt-nfs-bulk.mount --no-pager -n 100; echo ':: tailscale peers'; tailscale status; echo ':: tailscale dns'; tailscale dns status; echo ':: resolve kepler'; getent ahosts kepler || true; resolvectl query kepler || true; echo ':: nfs filesystems'; grep nfs /proc/filesystems || true; echo ':: modules'; lsmod | grep -E '(^nfs|sunrpc|lockd)' || true"

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

deploy-orion:
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_CONFIG="builders = $(just _builders orion)
    max-jobs = 1
    builders-use-substitutes = true"
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
