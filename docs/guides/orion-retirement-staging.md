# Orion retirement staging

**Status:** Operator authorized Kepler bulk staging on 2026-09-07. The operator subsequently declared Gemini expendable and authorized its deletion.
All three encrypted archives passed authenticated readback and SHA-256
recording. Staging completed successfully at approximately 09:01 -03.

Destination: Kepler `/bulk/orion-retirement-20260907`, owner `erik`, mode 0700.
Use a separate hard NFS mount on Orion; its ordinary bulk mount is soft.
Archives are encrypted to Orion's existing Ed25519 SSH host public key.
Recovery requires `/etc/ssh/ssh_host_ed25519_key` on Orion; do not rotate or
remove that identity during this operation. Never copy its plaintext private key.

Run from the operator workstation:

```sh
ssh -p 2222 erik@kepler 'test "$(findmnt -n -o SOURCE --target /bulk)" = bulk-pool/data && sudo -n install -d -m 0700 -o erik -g users /bulk/orion-retirement-20260907'
ssh -p 2222 erik@orion 'sudo -n install -d -m 0755 /mnt/orion-retirement-bulk && sudo -n mount -t nfs -o hard,vers=4.2,nosuid,nodev,noexec kepler:/bulk /mnt/orion-retirement-bulk'
```

The following root shell body runs on Orion in transient systemd unit
`orion-retirement-stage-20260907`. This is an explicitly requested one-time
operation, not a standing unattended identity or timer. Refuse existing outputs.

```bash
set -euo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
umask 077
dest=/mnt/orion-retirement-bulk/orion-retirement-20260907
age=/nix/store/b8mq9lqr30vlmx661xhp0cwvhyns29p6-age-1.3.2/bin/age
tar=/home/erik/.nix-profile/bin/tar
test -x "$age"
test "$(findmnt -n -o SOURCE --target /mnt/orion-retirement-bulk)" = kepler:/bulk
findmnt -n -o OPTIONS --target /mnt/orion-retirement-bulk | grep -qw hard
install -d -m 0700 /var/lib/orion-retirement-20260907
test ! -e /var/lib/orion-retirement-20260907/root
btrfs subvolume snapshot -r / /var/lib/orion-retirement-20260907/root
install -d -m 0700 /projects/.retirement-snapshots
btrfs subvolume snapshot -r /projects /projects/.retirement-snapshots/20260907
archive() {
  name=$1
  source=$2
  sudo -n -u erik test ! -e "$dest/$name.tar.age"
  sudo -n -u erik test ! -e "$dest/$name.tar.age.part"
  "$tar" --acls --xattrs --numeric-owner --sparse -cpf - -C "$source" . |
    "$age" -R /etc/ssh/ssh_host_ed25519_key.pub |
    sudo -n -u erik dd of="$dest/$name.tar.age.part" conv=excl,fsync status=none
  sudo -n -u erik cat "$dest/$name.tar.age.part" |
    "$age" -d -i /etc/ssh/ssh_host_ed25519_key |
    "$tar" -tf - >/dev/null
  sudo -n -u erik mv "$dest/$name.tar.age.part" "$dest/$name.tar.age"
  sudo -n -u erik sha256sum "$dest/$name.tar.age"
}
archive gemini /var/lib/orion-retirement-20260907/root/var/lib/nixos-containers/gemini
archive projects /projects/.retirement-snapshots/20260907
archive models /opt/models
```

Gemini's initial archive is filesystem crash-consistent, not application-consistent:
it was running at snapshot time. The operator explicitly accepted discarding the
container on 2026-09-07; a native-session handoff, final quiesced capture and
application restore are no longer retirement prerequisites. Keep the verified
initial archive as best-effort recovery. Models/Steam require a final stopped-writer
verification before their disk is changed. A partial archive is never a deletion gate.

Monitor with `systemctl status orion-retirement-stage-20260907` on Orion and
`du -h /bulk/orion-retirement-20260907` on Kepler. Retain the source snapshots
through archive verification. They consume additional space if source files change.

Current combined projects/models exceed a 480 GB disk. Kepler staging does not
change that: retain overflow there until a larger SSD or an explicit local
retention set is chosen. `/projects`, `/opt/models` and Steam's bind remain
unchanged until the migration layout is reviewed against exact device IDs.


## Temporary maintenance hold

The live `nixos-upgrade.timer` was due at 04:00 with automatic reboot still
allowed. Pause its future activation during staging (the upgrade service must
be inactive first):

```sh
ssh -p 2222 erik@orion 'test "$(systemctl show nixos-upgrade.service -p ActiveState --value)" = inactive && sudo -n systemctl stop nixos-upgrade.timer'
```

The initial runtime hold was insufficient: live activation started the missed
persistent upgrade job, which replaced the next-boot target with upstream main.
Boot-only deployment repaired that target. Both review branches now set
`system.autoUpgrade.enable = false` until integration; no timer/service can
restart the stale source after deployment or reboot. Re-enable in source and
deploy only after retirement and storage changes land on main, keeping
`system.autoUpgrade.allowReboot = false`.

## Authorized Gemini removal

Build and deploy the reviewed host-stability worktree with `just switch-orion`;
its configuration removes `orion-gemini`, the private bridge/NAT/preprovisioner,
and Gemini's Syncthing/SSH/launcher references. Do not activate the separate
storage-cutover worktree while the staging service still reads `/opt/models`.
Copy the built host-stability closure (no activation) and inspect the diff:

```sh
NIX_SSHOPTS='-p 2222' nix copy --to 'ssh://erik@orion?remote-program=sudo%20-n%20nix-store' /nix/store/7rgwd6f5jm9jgpm3px4ajfjiq5gxhfj8-nixos-system-orion-26.11.20260902.3ed67ec
ssh -p 2222 erik@orion '/nix/store/7rgwd6f5jm9jgpm3px4ajfjiq5gxhfj8-nixos-system-orion-26.11.20260902.3ed67ec/sw/bin/nvd diff /run/current-system /nix/store/7rgwd6f5jm9jgpm3px4ajfjiq5gxhfj8-nixos-system-orion-26.11.20260902.3ed67ec'
```

Preview affected units without activation:

```sh
ssh -p 2222 erik@orion 'sudo -n /nix/store/7rgwd6f5jm9jgpm3px4ajfjiq5gxhfj8-nixos-system-orion-26.11.20260902.3ed67ec/bin/switch-to-configuration dry-activate'
```

Before switching, preserve the hard
NFS staging mount and active staging service. Re-stop the upgrade timer after
activation: upstream main can still contain Gemini until integration lands.

After `gemini.tar.age` exists (promotion follows authenticated readback), and
after the deployed configuration no longer declares Gemini, remove only its
inactive root. The retained root snapshot continues to hold its old disk extents.
No snapshot cleanup is included here. Run from the operator workstation:

```sh
ssh -p 2222 erik@orion 'sudo -n bash -s' <<'SH'
set -euo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
sudo -n -u erik test -s /mnt/orion-retirement-bulk/orion-retirement-20260907/gemini.tar.age
test ! -e /etc/nixos-containers/gemini.conf
test "$(systemctl show container@gemini.service -p ActiveState --value)" = inactive
root=/var/lib/nixos-containers/gemini
test -d "$root"
test ! -L "$root"
if findmnt -rn -o TARGET | awk -v root="$root" '$0 == root || index($0, root "/") == 1 { found=1 } END { exit !found }'; then
  echo "Refusing deletion: Gemini still has mounts" >&2
  exit 1
fi
# NixOS marks /var/empty immutable. Clear only this retired container path.
if test -d "$root/var/empty"; then
  test ! -L "$root/var/empty"
  chattr -i "$root/var/empty"
fi
rm -rf --one-file-system -- "$root"
test ! -e "$root"
SH
```

Remove the retired container's rendered host secret copies after those same
checks. These are copies, not the shared Sops credential source:

```sh
ssh -p 2222 erik@orion 'sudo -n bash -s' <<'SH'
set -euo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
test ! -e /etc/nixos-containers/gemini.conf
test ! -e /var/lib/nixos-containers/gemini
root=/var/lib/gemini
test -d "$root"
test ! -L "$root"
if findmnt -rn -o TARGET | awk -v root="$root" '$0 == root || index($0, root "/") == 1 { found=1 } END { exit !found }'; then
  echo "Refusing deletion: Gemini secret directory still has mounts" >&2
  exit 1
fi
rm -rf --one-file-system -- "$root"
test ! -e "$root"
SH
```

External Tailnet device registration remains a separate homelab-iac cleanup;
never revoke shared fleet credentials.

## Initial retirement result, 2026-09-07 (historical)

Gemini's 135,687,037,556-byte archive passed authenticated decryption and tar-read
verification, then was promoted to `gemini.tar.age` at about 02:04 -03.
SHA-256 completed at about 02:28 -03; projects copying started next. Models
remain queued. Gemini SHA-256:
`7e77acd70aea05b0cb591eb04f0e9e3ceb10dee08d2d04be99d858934b64d73e`.

`just switch-orion` completed and deploy-rs confirmed activation. Active system:
`/nix/store/dz2c30pwv9nppxpdxls97334mhj4rdk4-nixos-system-orion-26.11.20260902.3ed67ec`.
The kernel and fstab match the previous system. SSH, Tailscale, Nix cache, Home
Manager, rootless inference/backup containers and staging are healthy; no failed
units. Native Herdr/tmux/Codex/Claude/OpenCode/Neovim resolve in a fresh login shell.

The inactive Gemini root and `/var/lib/gemini` rendered secret copies were deleted.
Its immutable `var/empty` flag was cleared only inside the retired root. The
read-only source snapshot and encrypted archive remain; immediate root disk
reclamation is not expected. `nixos-upgrade.timer` is paused again: do not resume
it until the retirement source is integrated into upstream main, otherwise a
future boot-target update could reintroduce Gemini. No disk cutover occurred.

## Latest storage result

Projects: 386,625,245,540 bytes; authenticated readback and SHA-256 passed:
`2c322be11db8608ed274f097d0e80543cf43c476f3fb5bb209744c79d548b8e6`.
Models: 367,365,647,988 bytes; authenticated readback passed at 08:02 -03;
final SHA-256 completed at approximately 09:01 -03:
`96025cee2e835609e8b3828190c40f4d99db897f78f72a176ef202751094385c`.
All archives are promoted, with no `.part` remaining. The staging journal records
`Deactivated successfully`; inactive/dead, Result=success, ExecMainStatus=0.
The transient unit is now unloaded, as expected.

The separate storage candidate is active: SanDisk hosts projects and the active
22 GiB model; Kingston hosts games. Steam and inference recovered, with no
failed system units. Both review branches disable automatic upgrades until
integration. Current and next-boot fstabs agree after repairing a missed
upgrade job's stale boot deployment. The storage candidate includes the exact
reviewed source/snapshot cleanup procedure; this earlier host-only candidate
must not be deployed over the now-active storage layout. Integrate the storage
candidate as the superset of both branches.

## Archive checksum manifest

Record the observed hashes beside the archives, refusing an existing manifest:

```sh
ssh -p 2222 erik@kepler 'umask 077; set -o noclobber; cat > /bulk/orion-retirement-20260907/SHA256SUMS' <<'SUMS'
7e77acd70aea05b0cb591eb04f0e9e3ceb10dee08d2d04be99d858934b64d73e  gemini.tar.age
2c322be11db8608ed274f097d0e80543cf43c476f3fb5bb209744c79d548b8e6  projects.tar.age
96025cee2e835609e8b3828190c40f4d99db897f78f72a176ef202751094385c  models.tar.age
SUMS
```

These hashes describe the encrypted files. Authenticated decryption/tar reads
already passed; this manifest write does not rerun those large reads. Recovery
requires Orion's existing SSH host private identity. Extract into a new empty
directory before reconciling files; do not overwrite live projects or Steam.

## Completed cleanup, 2026-09-07

At approximately 09:03 -03, the storage candidate's reviewed cleanup completed.
Old model copies were removed from Kingston; only `Steam` and `lost+found`
remain there. The two staging snapshots were deleted and Btrfs reclamation
finished. Both temporary mounts were released. Archives and `SHA256SUMS`
remain on Kepler, mode 0600 inside the mode-0700 staging directory.

Post-cleanup free space: system 228 GiB, projects/models 102 GiB, games 397 GiB.
Steam/Gamescope and inference remain healthy; no failed system units. Kepler's
`bulk-pool` is healthy. Orion's running and next-boot fstabs agree, upgrade
service/timer definitions are absent, and Gemini's config/root/rendered secrets
remain absent. Integration and later source-controlled upgrade re-enablement
remain; no commit, push, merge or unrelated host deployment was performed here.

## Integration complete

PR #284 merged as `e76eb7e`, then Orion activated the reviewed source. The
temporary upgrade hold is released: the installed command stages boot targets
without rebooting. Tuicr 0.24.0, Steam, inference, mount UUIDs and current/next-boot
fstab checks passed. The earlier hold and uncommitted-candidate statements above
are dated migration history; the [cutover guide](orion-storage-cutover.md) records
the final post-merge generation and service evidence.
