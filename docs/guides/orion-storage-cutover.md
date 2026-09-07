# Orion storage cutover

**Status:** Active and cleaned up on Orion, 2026-09-07. All archive readbacks and
checksum recording passed; reviewed old models and staging snapshots removed.
No formatting is required. Do not run disko's partition/format modes.

**Integration activation gate:** the final candidate restores boot-only automatic
upgrades with `allowReboot = false`. Do not deploy it before its PR is merged
into main. Orion's currently deployed generation keeps upgrade units absent
until that post-merge switch; no runtime timer is resumed early.

| Device | Existing UUID | Destination |
|---|---|---|
| MP510 NVMe | `754e224d-40cb-4ad6-8152-970677417ed8` | System, unchanged |
| SanDisk SSD PLUS 480 GB | `d4511ef9-7f62-4f0f-86d2-ee015344c289` | Existing `/projects` subvolume plus new `/models` at `/opt/models` |
| Kingston SV300 480 GB | `88a7f0d3-2fa2-4354-a4cd-8cab451dce85` | Existing ext4 remounted at `/games`; Steam stays in `Steam/` |

The current chat model uses `Qwen3.8-27B-GGUF`, a 22 GiB directory. Copy it
to the new subvolume before activation. Other weights stay on the old disk
until the encrypted Kepler archive is verified; cleanup uses the exact list below.
They remain in Kepler staging until explicitly selected for local restoration.

Run this preparatory root shell on Orion, through SSH from this checkout:

```bash
set -euo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
disk=/dev/disk/by-id/ata-SanDisk_SSD_PLUS_480GB_193181805834-part1
test "$(blkid -s UUID -o value "$disk")" = d4511ef9-7f62-4f0f-86d2-ee015344c289
test "$(df -Pk /projects | awk 'NR==2 {print $4}')" -gt 31457280
install -d -m 0755 /mnt/orion-projects-top
mount -o subvolid=5 "$disk" /mnt/orion-projects-top
test ! -e /mnt/orion-projects-top/models
btrfs subvolume create /mnt/orion-projects-top/models
rsync -aHAX --numeric-ids --stats \
  --include='/Qwen3.8-27B-GGUF/***' --exclude='/*' \
  /opt/models/ /mnt/orion-projects-top/models/
rsync -aHAXnc --numeric-ids --itemize-changes \
  --include='/Qwen3.8-27B-GGUF/***' --exclude='/*' \
  /opt/models/ /mnt/orion-projects-top/models/
```

The second rsync must produce no differences. The script deliberately refuses
an existing target; after interruption, inspect the target and resume the rsync
commands explicitly. Do not recreate a populated subvolume.

Before activation: finish archive verification; stop writers using `/opt/models`
and Steam; record the current NixOS generation; verify no deleted backing files
or unexpected consumers. Activate only this reviewed branch through the owning
`just` deployment recipe. Check `/projects` and `/opt/models` resolve to the
SanDisk, `/games` to Kingston, Steam's bind requires `/games`, and the chat
endpoint recovers on the same model file. Keep the old model files throughout
the observation window. Any later deletion requires an exact reviewed list.

Gemini was separately retired on 2026-09-07 after the operator declared it
expendable and its initial encrypted archive passed authenticated readback.
Its temporary root snapshot was removed by the completed cleanup below.

## Built candidate, 2026-09-07

Full Orion build passed. Copy this candidate without activation and preview
its affected units while staging continues:

```sh
NIX_SSHOPTS='-p 2222' nix copy --to 'ssh://erik@orion?remote-program=sudo%20-n%20nix-store' /nix/store/9x70rlpc7dkq721id3lw8c1i16l9cip2-nixos-system-orion-26.11.20260902.3ed67ec
ssh -p 2222 erik@orion 'sudo -n /nix/store/9x70rlpc7dkq721id3lw8c1i16l9cip2-nixos-system-orion-26.11.20260902.3ed67ec/bin/switch-to-configuration dry-activate'
```

This preview is not permission to switch before archive verification and
stopped-writer checks above pass.

## Live consumer inventory

Checked 2026-09-07: `llama-chat` bind-mounts `/opt/models` with private mount
propagation. Steam's launcher owns processes with working directories/open
files on Kingston. `fuser` from the host alone is insufficient because the
model process runs in a separate mount namespace. Other running rootless
containers have no models/games bind mounts.

The models archive reads live `/opt/models`, including Steam. Stop Steam before
its files are captured, not only before mount cutover:

```sh
ssh -p 2222 erik@orion 'sudo -n systemctl stop display-manager.service && systemctl --user stop gamescope-session.service steam-launcher.service'
```

After all three archives are verified, also quiesce inference using the native
lifecycle commands before the final model checksum comparison:

```sh
ssh -p 2222 erik@orion 'systemctl --user stop steam-launcher.service && podman stop --time 60 llama-chat'
```

Recheck `/opt/models` consumers and all container mounts; do not force an
unmount or kill unrelated processes. Although the Steam launcher has `Restart=no`, Gamescope restarts it externally.
The display manager and Gamescope must stay stopped during the capture/cutover. Then perform
the reviewed switch. Restart the existing container so its private bind mount
is created against the new SanDisk mount, and restart Steam:

```sh
ssh -p 2222 erik@orion 'podman start llama-chat && sudo -n systemctl start display-manager.service'
```

Verify the model endpoint at `http://127.0.0.1:8080/health` on Orion, container
health, filesystem UUIDs inside and outside the container, and Steam library
visibility. Preserve old model files on Kingston throughout observation.

## Final cutover gate

All archives passed authenticated decryption/tar-read on 2026-09-07 at 08:02 -03.
The remaining models SHA-256 reads only Kepler's hard NFS staging mount; it no
longer reads `/opt/models`. It can finish while this mount-only cutover runs.
Preserve that NFS mount and the staging service. No network/kernel change is
part of the previewed cutover. Keep originals and source snapshots retained.

After stopping inference, perform the final read-only comparison:

```sh
ssh -p 2222 erik@orion 'sudo -n rsync -aHAXnc --numeric-ids --itemize-changes --include="/Qwen3.8-27B-GGUF/***" --exclude="/*" /opt/models/ /mnt/orion-projects-top/models/'
```

Require exit zero and no differences before `just switch-orion` from this
worktree. Recheck exact UUIDs and absence of old mount consumers immediately
before switching. Do not format or delete old model files.

Activation may start a persistent upgrade timer's missed job. Immediately stop
both timer and service to retain the reviewed boot target until source lands:

```sh
ssh -p 2222 erik@orion 'sudo -n systemctl stop nixos-upgrade.timer nixos-upgrade.service'
```

Verify the running system and `/nix/var/nix/profiles/system` resolve to the
cutover generation; inspect the upgrade journal for any completed boot activation.

## Observed cutover and upgrade hold

The stopped-inference checksum comparison returned zero with no differences.
The reviewed switch passed; all three disk UUIDs and Steam mount dependency
match the table. Restarted `llama-chat` sees SanDisk's `/models` subvolume
inside its private namespace and returns HTTP 200 from `/health`. Steam and
Gamescope are active, with no failed system units.

Stopping the upgrade timer alone proved insufficient: activation started its
missed persistent job and replaced the next-boot profile with old main.
`just deploy-rs-boot orion` repaired that profile; the subsequent reviewed
switch deployed `system.autoUpgrade.enable = false`. Upgrade service/timer
definitions are now absent, and current/next-boot fstabs agree. Re-enable in
source only after integration into main, keeping `allowReboot = false`.

## Reviewed source cleanup

This completes the authorized temporary move to Kepler. Run only after the
staging unit exits successfully and all three archive hashes are recorded.
Keep the encrypted archives and Orion host identity. The exact Kingston list
below excludes Steam and `lost+found`. Reject paths changed after models capture
began, symlinks, or nested mounts; inspect any rejection instead of overriding it.
Check inference health and its SanDisk container mount immediately beforehand.

```bash
ssh -p 2222 erik@orion 'sudo -n bash -s' <<'SH'
set -euo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
unit=orion-retirement-stage-20260907.service
test "$(systemctl show "$unit" -p ActiveState --value)" = inactive
test "$(systemctl show "$unit" -p Result --value)" = success
test "$(systemctl show "$unit" -p ExecMainStatus --value)" = 0
test "$(findmnt -n -o UUID --target /games)" = 88a7f0d3-2fa2-4354-a4cd-8cab451dce85
test "$(findmnt -n -o UUID --target /opt/models)" = d4511ef9-7f62-4f0f-86d2-ee015344c289
dest=/mnt/orion-retirement-bulk/orion-retirement-20260907
test "$(sudo -n -u erik stat -c %s "$dest/models.tar.age")" = 367365647988
names=(
  Qwen3.8-Flash-Next-NVFP4-FTW Qwen3-Embedding-0.6B-GGUF
  Qwen3.8-27B-DSpark-GGUF Qwen3.8-27B-GGUF
  datagov-needle-tags-v5-epoch-01.cact datagov-needle-tags-v5-epoch-02.cact
  datagov-needle-tags-v5-epoch-03.cact freetoken-validation-artifacts
  datagov-needle-tags-v5-epoch-04.cact Qwen3.8-27B-DFlash2-GGUF
  datagov-needle-tags-v2.cact Qwen3-8B-GGUF Qwen3-1.7B-GGUF
  datagov-needle-tags-v3.cact Qwen3.8-Flash-Next-IQ1S-Q8MTP-FTW-v1
  datagov-needle-tags-v5-epoch-05.cact Qwen3.8-Flash-Next-GGUF
  Qwen3.6-35B-A3B-GGUF datagov-needle-tags-v4.cact
)
for name in "${names[@]}"; do
  path=/games/$name
  test -e "$path" && test ! -L "$path"
  changed=$(find "$path" -xdev \( -newerct '2026-09-07 05:42:00-03:00' -o -newermt '2026-09-07 05:42:00-03:00' \) -print -quit)
  test -z "$changed"
  if findmnt -rn -o TARGET | awk -v root="$path" '$0 == root || index($0, root "/") == 1 { found=1 } END { exit !found }'; then
    echo "Refusing cleanup: mounted path $path" >&2
    exit 1
  fi
done
for name in "${names[@]}"; do
  rm -rf --one-file-system -- "/games/$name"
done
test -d /games/Steam
test -s /opt/models/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-IQ3_XXS.gguf
SH
```

Afterwards remove only the two read-only snapshots created by this staging
operation. Verify their recorded identities, then release temporary mounts:

```bash
ssh -p 2222 erik@orion 'sudo -n bash -s' <<'SH'
set -euo pipefail
export PATH=/run/current-system/sw/bin:/run/wrappers/bin
root=/var/lib/orion-retirement-20260907/root
projects=/projects/.retirement-snapshots/20260907
test "$(btrfs property get "$root" ro)" = ro=true
test "$(btrfs property get "$projects" ro)" = ro=true
btrfs subvolume show "$root" | grep -Eq 'UUID:[[:space:]]+3a33783b-1e62-7445-8c8b-5f5d858840ad$'
btrfs subvolume show "$projects" | grep -Eq 'UUID:[[:space:]]+b3b5eb02-e15d-144e-9085-74c265e93aa7$'
btrfs subvolume delete "$root"
btrfs subvolume delete "$projects"
btrfs subvolume sync /
btrfs subvolume sync /projects
umount /mnt/orion-projects-top
umount /mnt/orion-retirement-bulk
df -h / /projects /opt/models /games
SH
```

No forced unmounts. Preserve ordinary NFS mounts, unrelated snapshots, original
checkouts, and all Kepler archives. The snapshot deletion is not repeatable;
after interruption inspect which exact operations completed before resuming.

## Completed cleanup and final verification

The models SHA-256 completed at approximately 09:01 -03; staging exited
successfully. All three hashes are recorded in Kepler's
`/bulk/orion-retirement-20260907/SHA256SUMS` and the
[staging guide](orion-retirement-staging.md). Cleanup above completed at
approximately 09:03 -03, including Btrfs reclamation and temporary unmounts.
Do not rerun these one-time migration commands.

Kingston now contains only `Steam` and `lost+found`. The active 22 GiB model
remains on SanDisk. Free space: system 228 GiB; projects/models 102 GiB;
games 397 GiB. Inference returns HTTP 200, its private mount uses SanDisk,
Steam/Gamescope are active, and no system units are failed. Kepler's bulk pool
is healthy. All expected UUIDs, absent Gemini paths, and absent upgrade units
pass final checks.

Final running system:
`/nix/store/bilm4nmdjgg6k2hwd3nyqy5zplgy0sjg-nixos-system-orion-26.11.20260902.3ed67ec`.
Next-boot activation wrapper:
`/nix/store/v2fxca1ix2wfw6bfh2jfsv5hfzd2kcmw-activatable-nixos-system-orion-26.11.20260902.3ed67ec`.
Their fstabs agree. No reboot was required or tested.

This storage review branch is the integration superset: do not deploy the
earlier host-only candidate over this layout. Six-host dry builds, targeted
tmux regression, lint/format, documentation and live Orion checks passed.
Keep upgrades disabled until the source lands on main, then re-enable through
a reviewed source change while retaining `allowReboot = false`.

## Integration review follow-up

The candidate is rebased onto main's 2026-09-07 host reconciliation and OpenBao
fixes. Review removed retired Gemini Herdr/kubeconfig/diagnostic recipes and
Gemini-only tests, retaining shared Herdr checks under `tests/herdr-worklab`.
Alias checks now follow Orion/Apollo umbrella entry points. Native Orion
retains Tuicr through its Home Manager import; that final package addition
awaits deployment. The existing disk cutover and upgrade hold remain active.

The updated tests first reproduced the missing native Tuicr import and stale
Gemini command paths, then passed with the fixes. After rebase, 45 focused
checks pass, including upstream Apollo host checks. Lint, format, documentation
and commit-hook secret checks pass. The role `.feature` remains unautomated.

## Final upgrade configuration

The final integration candidate enables automatic boot-target staging while
keeping automatic reboot disabled. This avoids a second integration/rollout
solely to release the temporary hold. Merge the complete retirement/storage
source first, fetch and verify that main contains it, then use `just switch-orion`.
A missed persistent timer may run immediately; after merge its upstream source
already contains the new mounts and Gemini retirement. Verify the upgrade
service outcome, current/next-boot fstabs, absent Gemini and live services.
The historical maintenance-hold steps above describe the earlier deployed state.
