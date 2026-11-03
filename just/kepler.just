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
      --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 1 | tail -1)
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
      --builders "{{orion_builder}}" --builders-use-substitutes --max-jobs 1 --show-trace
    extra=$(mktemp -d)
    trap 'rm -rf "$extra"' EXIT
    ssh -p 2222 erik@{{ip_kepler}} \
      'sudo tar -C / -cpf - etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub etc/ssh/ssh_host_rsa_key etc/ssh/ssh_host_rsa_key.pub var/lib/tailscale/tailscaled.state home/erik/.config/sops/age/keys.txt' \
      | tar -xpf - -C "$extra"
    chmod 600 "$extra"/etc/ssh/ssh_host_*_key "$extra"/var/lib/tailscale/tailscaled.state "$extra"/home/erik/.config/sops/age/keys.txt
    export NIX_CONFIG="builders = {{orion_builder}}
    max-jobs = 1
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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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
        podman-compose-retrieval.service; do
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
      nix shell --builders "{{apollo_builder}}" --builders-use-substitutes \
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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

# kepler is a GPU host: an nvidia driver bump in the closure mismatches the
# running kernel module on a LIVE switch (breaks the AI stack — verified). Stage
# the new generation for next boot, then reboot to activate. Own window (AI
# serving restarts on reboot).
switch-kepler:
    just deploy-rs-boot kepler
    @echo ":: kepler staged for next boot. Reboot to activate (AI stack restarts):"
    @echo "   ssh -p 2222 erik@{{ip_kepler}} sudo systemctl reboot"

# Read-only Kepler secondary-DNS failure detail.
diagnose-kepler-dns:
    ssh -p 2222 erik@{{ip_kepler}} 'sudo systemctl status coredns.service --no-pager -l; sudo systemctl show coredns.service -p ActiveState -p SubState -p Result -p NRestarts; sudo ss -H -lntup "sport = :53"; sudo journalctl -u coredns.service -b --no-pager -n 80'

# Recover the existing listener after DHCP has assigned Kepler's LAN address.
recover-kepler-dns:
    ssh -p 2222 erik@{{ip_kepler}} 'sudo systemctl restart coredns.service'
    just p3-dns-verify

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
      https://loki.homelab.pastelariadev.com/loki/api/v1/query_range \
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

# Attribute current fast-pool writes without printing process arguments.
diagnose-kepler-io:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(jq -r '.hosts.kepler.tailscaleIp // empty' fleet.json)
    [ -n "$ip" ] || ip=$(just _host-ip kepler)
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=5 \
      -o ServerAliveInterval=3 -o ServerAliveCountMax=1 "erik@$ip" \
      'sudo bash -s' <<'REMOTE'
    set -euo pipefail
    test "$(zpool list -H -o health fast-pool)" = ONLINE
    declare -A before
    for io in /proc/[0-9]*/io; do
      pid=${io#/proc/}; pid=${pid%/io}
      before[$pid]=$(awk '$1 == "write_bytes:" { print $2 }' "$io" 2>/dev/null || true)
    done

    echo ":: fast-pool physical I/O (three one-second samples)"
    timeout 8 zpool iostat -v fast-pool 1 4

    echo ":: process write deltas during sample"
    printf '%12s  %-7s  %-24s  %s\n' bytes pid process cgroup
    {
      for io in /proc/[0-9]*/io; do
        pid=${io#/proc/}; pid=${pid%/io}
        current=$(awk '$1 == "write_bytes:" { print $2 }' "$io" 2>/dev/null || true)
        previous=${before[$pid]:-}
        [ -n "$current" ] && [ -n "$previous" ] || continue
        delta=$((current - previous))
        [ "$delta" -gt 0 ] || continue
        process=$(tr -cd '[:alnum:]_.@+-' <"/proc/$pid/comm" 2>/dev/null || printf unknown)
        cgroup=$(awk -F: '$1 == "0" { print $3 }' "/proc/$pid/cgroup" 2>/dev/null || true)
        printf '%12d  %-7s  %-24s  %s\n' "$delta" "$pid" "$process" "${cgroup:--}"
      done
    } | sort -nr | head -15 || true
    REMOTE

# Read-only filesystem allocation and largest top-level trees on Kepler.
diagnose-kepler-disk:
    ssh -p 2222 erik@{{ip_kepler}} 'df -h / /fast; sudo btrfs filesystem usage /; sudo btrfs device stats /; sudo btrfs scrub status /; sudo journalctl --no-pager _TRANSPORT=kernel | grep -Ei "BTRFS|Structure needs cleaning|I/O error|corrupt" || true; sudo zfs list -o name,mountpoint,used,available,recordsize; systemctl cat microvm@cp-1.service; pgrep -af "openwakeword|ha-train|huggingface|kaggle" || true; sudo du -x -d2 -B1 /nix /var /home 2>/dev/null | sort -nr | head -40; sudo du -x -d2 -B1 /home/erik/.local /home/erik/.cache /home/erik/openwakeword-training /home/erik/ha-train /home/erik/ha-hf /var/lib/microvms 2>/dev/null | sort -nr | head -40'

# Remove reproducible Hugging Face model caches only.
clean-kepler-model-cache:
    ssh -p 2222 erik@{{ip_kepler}} 'test "$(hostname)" = kepler; du -sh /home/erik/ha-hf /home/erik/hf-cache 2>/dev/null || true; rm -rf -- /home/erik/ha-hf /home/erik/hf-cache; df -h /'

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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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
        --max-jobs 1 nixpkgs#restic -c restic -o "sftp.command=$sftp_cmd" "$@"
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

deploy-kepler:
    #!/usr/bin/env bash
    set -euo pipefail
    export NIX_CONFIG="builders = $(just _builders kepler)
    max-jobs = 1
    builders-use-substitutes = true"
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
