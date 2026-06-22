# archinaut Migration — Execution Plan (session handoff)

Turn the BIQU B1 Klipper host (RPi3, Debian, `192.168.10.225`) into the NixOS
fleet host **`archinaut`**. This is a runnable checklist; the full rationale and
design is in the proposal:
**[`2026-06-16-printer-nixos-host.md`](2026-06-16-printer-nixos-host.md)**
(read §6a extras blocker, §6b moonraker exception, §9 SD bootstrap if anything
below is unclear).

Related: `klipper-biqu` repo (config source-of-truth) at
`references/repos/klipper-biqu`; host naming + locked decisions also in
`~/.claude/.../memory/archinaut_printer_host.md`.

## TL;DR — next steps in order

Scaffold is written and evals green (uncommitted). To execute:
**0** verify eval → **1** commit (optional) → **2** `just switch-orion` (aarch64
builds) → **3+4** flash SD, first boot wired, register sops host key → **3**
add `moonraker/secrets` → **5** `just switch-archinaut` → **6**
`just seed-archinaut` → **7** verify stack → **8** config backup
(`klipper-config-backup` service + Mainsail button) → **9** WiFi later. Old
Debian SD card = rollback throughout.

## Architecture at a glance (so this doc stands alone)

Responsibility boundary — **NixOS owns the machine, the repo owns the printer**:

| Layer | Owner | Where |
|---|---|---|
| OS, users, net, monitoring, package *versions*, MCU firmware *build* | NixOS `archinaut` | this flake |
| Klipper `printer.cfg` + calibration, `mainsail.cfg`, macros | `klipper-biqu` repo | `/var/lib/klipper` (mutable, rsync-seeded) |
| OrcaSlicer presets | `klipper-biqu` repo | laptop `just orca-sync` |
| `moonraker.conf` | **NixOS (declarative)** | `services.moonraker.settings` |

Why it works: `services.klipper.mutableConfig = true` seeds `printer.cfg` from
the repo once, then leaves it — so `SAVE_CONFIG` + Mainsail edits persist.
Stock klipper can't parse `[autotune_tmc]`/`[motor_constants]`, so the
`klipper-host` module overlays the klipper package to vendor
`klipper_tmc_autotune`'s `klippy/extras`. The Pi (1 GB, aarch64) never builds —
orion builds under qemu binfmt and the Pi substitutes.

## Locked decisions (do not re-litigate)

- **Keep the RPi3.** aarch64 closure built on **orion** (binfmt qemu), Pi only
  substitutes.
- **Services-only.** NixOS owns OS + packages + MCU-firmware *build*. ALL config
  (klipper `printer.cfg`, `mainsail.cfg`, OrcaSlicer presets) lives in the
  `klipper-biqu` repo. `moonraker.conf` is the one exception → declarative
  `services.moonraker.settings`.
- **Klipper third-party extras: vendored** into the klipper package (overlay
  pulls `klipper_tmc_autotune` for `[autotune_tmc]`/`[motor_constants]`).
- **MCU firmware: build-only**, flash manual (SD bootloader).
- **Webcam: minimal ustreamer**, single C270.
- **klipper-backup PAT: sops-nix.**
- **Network: wired for first boot**, migrate to WiFi later (router reservation
  on the new MAC).

## Already done (state at handoff)

- Backups in `~/Documents/erik/backups/`: `klipper-biqu-*.tar.gz` (repo) +
  `archinaut-live-config-*.tar.gz` (authoritative live Pi snapshot).
- Live config pulled into the `klipper-biqu` working tree — only `printer.cfg`
  differs from the old repo (BLTouch `z_offset` 1.350 → **1.300**).
  **Uncommitted in the klipper-biqu repo** — commit it there when ready.
- **Scaffold written & evaluating green, uncommitted** in `desktop-nixos`:
  - `modules/services/klipper-host.nix`
  - `modules/hardware/archinaut-hardware.nix`
  - `modules/hosts/archinaut/default.nix`
  - `modules/hosts/orion/default.nix` (+ `boot.binfmt.emulatedSystems`)
  - `modules/packages/shared.nix` (x86-only pkgs gated behind `isx86_64`)
  - `justfile` (`build-archinaut-sd`, `switch-archinaut`, `seed-archinaut`,
    `ip_archinaut`)
  - `docs/proposals/2026-06-16-printer-nixos-host.md` (RFC, untracked)

Verify it still evals before proceeding:
```bash
cd ~/Documents/erik/desktop-nixos
just lint && just fmt-check
nix eval .#nixosConfigurations.archinaut.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.archinaut.config.system.build.sdImage.drvPath
```

## Step 1 — commit the scaffold (optional, on a branch)

New files must be `git add`ed for flake eval to see them (already staged). If
committing: feature branch, conventional commit, **no AI attribution**.

## Step 2 — deploy orion (enables aarch64 builds)

orion gains `boot.binfmt.emulatedSystems = ["aarch64-linux"]`.
```bash
just switch-orion
ssh -p 2222 erik@192.168.10.220 'cat /proc/sys/fs/binfmt_misc/qemu-aarch64 | head -1'  # should exist
```

## Step 3 — sops: register the archinaut host key + add secrets

> The HA power plugin (`[power biqu]`) is **opt-in** via
> `printer.haPower.enable` (default off) so the host builds/boots without the
> secret. The base print stack (klipper/moonraker/mainsail/webcam) needs no
> sops secret. Do this step only when you want the HA zigbee-plug integration,
> then set `printer.haPower.enable = true;` in the archinaut host module.

Until the secret exists, leave `printer.haPower.enable` off.
1. Get archinaut's host age key. Easiest: first-boot the SD (Step 4) headless,
   then derive the age key from its SSH host key:
   `ssh -p 2222 erik@192.168.10.225 'cat /etc/ssh/ssh_host_ed25519_key.pub' |
    nix run nixpkgs#ssh-to-age`
2. Add that age recipient to `.sops.yaml` under the archinaut creation rule.
3. Add the `moonraker/secrets` entry to `secrets/sops/secrets.yaml` — a
   moonraker secrets ini:
   ```
   [home_assistant]
   token = <HA long-lived token>
   ```
4. `sops updatekeys secrets/sops/secrets.yaml` to re-encrypt to the new key.

(Chicken-egg: Step 3.1 needs the host booted, so it interleaves with Step 4.
Deploy `switch-archinaut` AFTER the key is registered.)

## Step 4 — build + flash the SD image

```bash
just build-archinaut-sd
lsblk                                   # identify the BLANK new card = /dev/sdX (whole disk!)
zstd -dc result-archinaut-sd/sd-image/*.img.zst \
  | sudo dd of=/dev/sdX bs=4M oflag=direct status=progress conv=fsync
sync
```
Swap the card into the Pi. **Keep the old Debian SD intact = instant rollback.**
Power on (wired ethernet). First boot expands rootfs (may reboot once).
```bash
ssh -p 2222 erik@192.168.10.225 'systemctl --failed'
```

## Step 5 — first real deploy

After Step 3 secrets are registered:
```bash
just switch-archinaut          # evaluates locally, builds aarch64 on orion, pushes to Pi
```

## Step 6 — seed config from the repo

```bash
just seed-archinaut            # rsync klipper-biqu/printer_data/config → /var/lib/klipper, restart
```
`mutableConfig=true` keeps it; `SAVE_CONFIG` + Mainsail edits now persist.

## Step 7 — verify the print stack

```bash
ssh -p 2222 erik@192.168.10.225 'systemctl status klipper moonraker'
# Mainsail UI:
xdg-open http://192.168.10.225
# webcam stream: http://192.168.10.225:8080/stream  (add in Mainsail webcam settings)
```
Confirm in Mainsail: klippy connects (no "Unknown config object" — proves the
vendored autotune extras loaded), bed mesh/PID/input-shaper present,
`[power biqu]` toggles the HA plug.

## Step 8 — config backup → git (klipper-config-backup, DONE 2026-06-21)

The klipper-backup *tool* is NOT used: its wipe-and-replace model would delete
`orcaslicer/` from the **shared** `klipper-biqu` repo. Instead, a bespoke,
shared-repo-safe NixOS service (in `klipper-host.nix`):

- `systemd.services.klipper-config-backup` + a **daily timer** — resets a work
  clone to `origin/main`, mirrors `/var/lib/klipper` → `printer_data/config/`
  **only**, commits/pushes just that subtree. `orcaslicer/` is never touched.
- Auth: a per-repo **SSH deploy key** (write-scoped to `klipper-biqu`), no PAT.
  Generated on the Pi (`~/.ssh/klipper_backup_deploy`); reflash → regenerate +
  re-add the deploy key on GitHub. `git_protocol=ssh` via `core.sshCommand`.
- **Mainsail button**: `BACKUP_CONFIG` macro (klipper-biqu `shell_command.cfg`)
  → `gcode_shell_command` → scoped NOPASSWD sudo → starts the service.

Verified end-to-end: a real config change pushed as `auto: klipper config
backup`, touching only `printer_data/config/`, `orcaslicer/` intact.

## Step 9 — WiFi migration (later)

1. Add SSID/PSK to sops (`secrets/sops/secrets.yaml`).
2. In `modules/hardware/archinaut-hardware.nix`: enable `wpa_supplicant`/
   networkmanager with the sops PSK; keep wired as fallback.
3. Router: reserve `192.168.10.225` on the WiFi MAC.
4. `just switch-archinaut`, then unplug ethernet and confirm reachability.

## Known gotchas

- **Old SD card = rollback.** Don't wipe it until archinaut is proven.
- **First switch before sops secret** → moonraker power plugin unit fails (rest
  of the stack is fine). Register the secret first.
- **klipper overlay pin** (`klipper_tmc_autotune` rev) needs bumping when klipper
  itself bumps and the extras break — update rev + `hash` in `klipper-host.nix`.
- **RPi3 switch time is slow** even substitute-only — expected, tolerated.
- **`moonraker.conf` is declarative now** — edit
  `services.moonraker.settings`, not a repo file. All `[update_manager …]`
  git-repo entries from the Debian conf were intentionally dropped.
- **1 GB RAM**: tmpfs `/tmp` is forced off + zram on; don't re-enable tmpfs.

## Quick reference

| | |
|---|---|
| Host attr | `archinaut` (`.#archinaut`) |
| Pi IP / SSH | `192.168.10.225` (wired/eth0, DHCP-reserved) : 2222 — wifi `.226` is Phase-9. Roaming/admin: reach via tailscale |
| Build host | orion `192.168.10.220` (aarch64 binfmt) |
| Config dir (mutable) | `/var/lib/klipper` |
| Config source-of-truth | `klipper-biqu` repo (`references/repos/klipper-biqu`) |
| MCU serial | `/dev/ttyS1` (GPIO mini-UART; 3B+ mainline DTB) |
| Mainsail | `http://192.168.10.225` |
| Webcam | `http://192.168.10.225:8080/stream` (ustreamer, C270) |

## Post-bring-up config hardening — implementation plan (2026-06-20)

Printer is **operational** (klippy `ready`, Mainsail, webcam, MCU on
`/dev/ttyS1`). **Power-sequencing is retired** — kernel-direct boot landed
(2026-06-21): the Pi boots fine with the printer powered on, no u-boot stage to
hang, and reaches `ready` unattended on cold boot. Several fixes landed live / in
moonraker's DB only — make them declarative so a **reflash reproduces the working
state**. Each item lists the change + verify. Order: 1→2 required, 3→4 optional,
5 doc, 6 external.

### 1. Declarative webcam (REQUIRED — reflash-safe)
The C270 is registered only in moonraker's database (`source:"database"`) — a
fresh reflash loses it. Add a `[webcam]` block to `services.moonraker.settings`
in `modules/services/klipper-host.nix`:
```nix
"webcam C270" = {
  location = "printer";
  service = "mjpegstreamer-adaptive";
  target_fps = 15;
  stream_url = "http://192.168.10.225:8080/stream";
  snapshot_url = "http://192.168.10.225:8080/snapshot";
};
```
- Optional robustness: proxy ustreamer through the mainsail nginx at `/webcam/`
  and use **relative** URLs, so it's IP-independent (survives wired↔wifi).
- Verify: `just dry archinaut`; after `just switch-archinaut`,
  `curl localhost:7125/server/webcams/list` shows a `source:"config"` C270 and
  Mainsail renders the feed. (A config-defined webcam is read-only in the UI —
  delete the stale DB one via the API if it duplicates.)

### 2. Fix the `dialout` comment (REQUIRED — correctness)
`klipper-host.nix` ~L78 reads "MCU is USB-serial on the SKR 1.4". It is **GPIO
UART `/dev/ttyS1`** (mini-UART). The `dialout` group stays (ttyS1 is
group `dialout`); fix the comment only.

### 3. Drop kernel serial consoles (OPTIONAL — hygiene)
The sd-image adds `console=ttyS0,115200n8 console=ttyAMA0,115200n8`. Harmless
(klipper is on ttyS1, not those) but they spawn failing `serial-getty@` units
and are the u-boot-console hazard if boot is ever reworked. Override
`boot.kernelParams` in `archinaut-hardware.nix` to keep only `console=tty0`.
Verify: `cat /proc/cmdline` post-switch shows no `console=ttyS0/ttyAMA0`.

### 4. ustreamer `--workers 2` (OPTIONAL — if the feed stalls)
Single worker can choke with multiple viewers (transient "loading forever" seen
once). Add `--workers=2` (+ `--drop-same-frames=30`) to the ustreamer
`ExecStart`. Verify: two browser tabs stream concurrently.

### 5. (this doc) stale-ref sweep — done above (`.225`→`.187`, MCU row).

### 6. External — `klipper-biqu` repo (user-owned, do NOT auto-push)
Commit `printer.cfg` (`[mcu] serial=/dev/ttyS1`). The recovered `mainsail.cfg`
and vendored `KAMP/` are **gitignored** working-tree files (update_manager-style)
— they round-trip via klipper-backup once Step 8 is set up; until then they live
only in the working tree + on the Pi.

### Kernel-direct boot — DONE (2026-06-21)
Power-sequencing retired. The host boots via GPU-firmware-direct kernel load
(no u-boot), so the Klipper MCU on the GPIO UART no longer hangs boot. Reaches
`ready` unattended on cold boot with the printer powered. Key facts learned
during bring-up (board is a **Pi 3 Model B+**, not a plain 3B):
- **DTB:** must be the mainline kernel's `bcm2837-rpi-3-b-plus.dtb` (copied from
  the kernel package), NOT the foundation `bcm2710-*` from raspberrypifw. The
  foundation DTB boots but leaves the whole USB tree (DWC2 → LAN7515 hub →
  lan78xx Gigabit ethernet + webcam) dead; the plain 3B DTB misses the 3B+
  ethernet.
- **MCU serial:** `/dev/ttyS1` under that DTB (mini-UART; PL011=ttyAMA0 is
  bluetooth). `/dev/ttyS0` is a phantom 8250 port → I/O error.
- **Thermal race:** `bcm2835_thermal` registers `thermal_zone0` a few seconds
  late; klipper has a preStart wait so `[temperature_sensor raspberry_pi]`
  doesn't hard-halt klippy.
- **MCU recovery:** the MCU is on the printer PSU (independent of the Pi) so it
  enters shutdown on a host reboot; `klipper-mcu-recover.service` issues one
  FIRMWARE_RESTART after boot so klippy reaches `ready` without manual steps.

See `docs/proposals/2026-06-20-archinaut-kernel-direct-boot.md` and the
`archinaut-kernel-direct` + `klipper-host` modules.
