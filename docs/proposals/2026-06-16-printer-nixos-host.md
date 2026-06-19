# `archinaut` — BIQU B1 Klipper Printer as a NixOS Fleet Host

**Date:** 2026-06-16
**Status:** Proposal (skeleton — judgment sections marked `TODO(erik)`)
**Owner:** erik
**Target host:** `archinaut` (new) — Raspberry Pi 3, `192.168.10.225`
**Related:** sister repo [`klipper-biqu`](../../references/repos/klipper-biqu) (printer config + as-built reference); fleet host pattern follows `discovery`.

> Naming: fleet hosts are real spacecraft matched to machine focus. **Archinaut
> One** (Made In Space / Redwire) is the in-space 3D-printing + robotic-assembly
> craft — the printer host's namesake.

---

## 1. Goal

Bring the BIQU B1's Klipper host into the dendritic NixOS fleet (declarative OS,
fleet autoUpgrade, alloy monitoring, btrfs snapshots) **without taking ownership
of any printer config**. NixOS manages the *machine*; the `klipper-biqu` repo
manages the *printer*.

### Responsibility boundary (the core principle)

| Layer | Owner | Where it lives |
|---|---|---|
| OS, users, network, monitoring, snapshots | **NixOS** (`archinaut` host) | this flake |
| Package **versions** — klipper / moonraker / mainsail | **NixOS** (nixpkgs pins) | this flake |
| MCU **firmware** build + flash (SKR 1.4 / LPC1768) | **NixOS** (`services.klipper.firmwares`) | this flake |
| Klipper config — `printer.cfg`, `moonraker.conf`, macros, calibration | **`klipper-biqu` repo** | `printer_data/config/` |
| Mainsail config — `mainsail.cfg` (macro include) | **`klipper-biqu` repo** | `printer_data/config/` |
| OrcaSlicer presets — machine / filament / process | **`klipper-biqu` repo** | `orcaslicer/` |

NixOS never templates, generates, or owns a config file. It provisions a
**mutable** config dir and the services that read it; the repo is the single
source of truth for everything inside that dir.

## 2. Current state (baseline)

| Part | Detail |
|---|---|
| Printer | BIQU B1, BTT SKR 1.4 (LPC1768), `v0.13.0-694` |
| Host | Raspberry Pi 3, Debian 12, Python 3.11, **`192.168.10.225`** |
| Stack | Klipper host + Moonraker + Mainsail + crowsnest (C270 webcam) |
| Config VCS | `klipper-backup` → `klipper-biqu` repo, `printer_data/config/`. **Stale** — `.env` unconfigured on the Pi. |
| Calibration | PID, input shaper X/Y, pressure advance, bed mesh, z_offset — all in `printer.cfg` autosave `#*#` block |

As-built hardware/calibration detail: `klipper-biqu/references/README.md`.

## 3. Locked decisions

1. **Keep the RPi3.** No hardware swap. ⇒ never build on-device (1 GB RAM).
2. **Services-only config.** NixOS owns packages + services; **all** config
   (Klipper `printer.cfg`/`moonraker.conf`, Mainsail `mainsail.cfg`, OrcaSlicer
   presets) stays mutable and lives in the `klipper-biqu` repo — see §1
   responsibility boundary. Nix never owns a config file.
3. **Host value = OS + firmware + package maintainability.** The win is
   reproducible OS, fleet autoUpgrade, declarative klipper/moonraker/mainsail
   **versions**, and managed MCU firmware — *not* config management.
4. **MCU firmware: build-only.** `services.klipper.firmwares` builds the
   LPC1768 `.bin`; flashing stays manual (SD bootloader copy). No auto-flash.
5. **Webcam: minimal ustreamer.** One systemd unit for the single C270
   (720p MJPEG). No crowsnest port.
6. **klipper-backup PAT via sops-nix** (fleet secret pattern), placed on
   activation — not a hand-dropped `.env`.

## 4. The constraint that shapes everything — `SAVE_CONFIG`

`services.klipper.settings` renders config into read-only `/nix/store` →
`SAVE_CONFIG` fails and calibration is lost. **Resolution:** set
`services.klipper.configDir = "/var/lib/klipper/config"` (mutable). NixOS never
templates the tuning; Klipper and Mainsail own that file at runtime.

## 5. Architecture

### 5.1 New aspect — `flake.modules.nixos.klipper-host`
- `services.klipper` — mutable `configDir`; optional `firmwares.skr14` for
  LPC1768 flash (`klipper-flash-*`).
- `services.moonraker` — `allowSystemControl = true`, mutable config,
  `klipperSocket` wired.
- `services.mainsail.enable = true`. Package ships the UI + default
  `mainsail.cfg`; the repo's `mainsail.cfg` (macro include) wins in the mutable
  configDir.
- `services.klipper.firmwares.skr14` — **build-only** (`.bin` artifact); flash
  manually via SD bootloader. No `enableKlipperFlash`.
- `systemd.services.ustreamer` — single C270, 720p MJPEG. crowsnest is not a
  stock NixOS service; minimal ustreamer unit (decided — no crowsnest parity).

### 5.2 New host — `modules/hosts/archinaut/default.nix`
Thin, mirrors `discovery`:
```
imports = [ profile-base profile-server klipper-host archinaut-hardware
            first-boot alloy btrfs-snapshots ];
nixpkgs.hostPlatform = "aarch64-linux";
modules.upgradeHealthCheck.criticalUnits =
  [ "sshd.service" "tailscaled.service" "klipper.service" "moonraker.service" ];
```

### 5.3 Build / cache (the RPi3 blocker)
- aarch64 closure built on **orion** via `boot.binfmt.emulatedSystems =
  ["aarch64-linux"]` (orion is x86_64 → qemu emulation), pushed to the existing
  nix-cache.
- Pi only **substitutes**. New `just` recipe wraps
  `--build-host orion --target-host archinaut` (never open-code — CLAUDE.md).
- Bootstrap: build the SD image on orion, flash, first boot headless (see §9).

### 5.4 Config flow — repo is the single source of truth
- `first-boot` oneshot seeds `/var/lib/klipper/config` from `klipper-biqu`
  (`printer_data/config/`), then NixOS leaves the dir alone forever.
- Runtime writes (`SAVE_CONFIG`, Mainsail edits, `mainsail.cfg`) → push back to
  the repo via **klipper-backup**, whose GitHub PAT `.env` is provisioned by
  **sops-nix** on activation (not hand-dropped). Klipper + Mainsail config
  round-trip through the repo.
- OrcaSlicer presets → repo via the laptop `just orca-sync` flow (unchanged).
- Net: every config layer in §1's table is versioned in `klipper-biqu`; the Pi's
  config dir is a working copy, not the master.

## 6. Open questions — `TODO(erik)` (judgment)

- ~~aarch64 build host~~ → **orion** (binfmt emulation). Locked.
- ~~RPi3 switch time~~ → **tolerable**. Locked.
- ~~seed: flake input vs rsync~~ → **rsync** (state, not a buildable input).
  Locked.
- **Migration downtime + rollback:** SD reflash = printer down + Debian erased.
  Mitigation: **new SD card** (old Debian SD kept intact as instant rollback —
  swap card to revert). Build/verify everything before flashing.

> **Pre-migration safety (done 2026-06-16):** live config pulled off the Pi —
> repo was stale only on BLTouch `z_offset` (1.350 → live **1.300**). True
> as-built snapshot archived under `~/Documents/erik/backups/`.

## 6a. ⚠️ Fundamental blocker — third-party klippy extras

The live `printer.cfg` uses klippy **extensions not in nixpkgs' `klipper`**, and
NixOS can't install them moonraker's way (`update_manager` git-clone + pip into
`klippy-env` — impossible on a read-only store):

| Config section | Source | On NixOS |
|---|---|---|
| `[autotune_tmc]`, `[motor_constants …]` | `klipper_tmc_autotune` (Frix/andrewmcgr) | **must vendor into the klipper package** |
| `[shaketune]` | `klippain-shaketune` | vendor, or keep disabled (it's commented now) |
| KAMP (`LINE_PURGE`, `KAMP_Settings.cfg`) | macros only | fine — `.cfg` includes, no python |
| `mainsail.cfg` | macros only | fine |

Stock `klippy` **hard-fails** on the unknown sections. **Decision: vendor
extras** — overlay the klipper derivation to drop `klipper_tmc_autotune`'s
`klippy/extras/*.py` (`autotune_tmc.py`, `motor_constants.py`, motor DB) into
`$out/lib/klipper/klippy/extras/`. Keeps runtime silent auto-tuning. Cost:
maintain the overlay/pin across klipper bumps. (shaketune stays disabled — add
the same way if/when re-enabled.)

This is the dominant effort of the migration, not the OS/SD work.

## 6b. Moonraker is declarative (the one config exception)

The NixOS moonraker module runs from a **Nix-generated** config — so
`moonraker.conf` becomes `services.moonraker.settings` (declarative), not
repo-mutable. Acceptable: you named *klipper / orca / mainsail* as the
repo-owned set; moonraker is stable infra (auth, history, power plugin), not
tuning. Translation notes from the live conf:
- Keep: `[server]`, `[authorization]` (LAN trusted_clients), `[octoprint_compat]`,
  `[history]`, `[announcements]`, `[file_manager]`.
- **Drop every `[update_manager …]` git_repo** (mainsail, crowsnest, sonar,
  klipper-backup, KAMP, shaketune, autotune) — NixOS owns versions; git-repo
  updaters are meaningless on a read-only store.
- `[power biqu]` (HA zigbee plug) → keep; its `{secrets.home_assistant.token}`
  moves to a moonraker secrets file provisioned by **sops-nix**.

## 7. Out of scope

MCU firmware changes, BTT Eddy probe upgrade, OrcaSlicer preset management
(laptop-side, unchanged).

> **Scaffold status (2026-06-17):** modules written, **evaluating green**, and
> the **aarch64 SD image built end-to-end on orion** (binfmt qemu) — the klipper
> overlay (`klipper_tmc_autotune`), moonraker, mainsail and ustreamer all
> compile on aarch64. `klipper-host`, `archinaut-hardware`, `hosts/archinaut`,
> orion binfmt (deployed), and `just build-archinaut-sd` / `switch-archinaut` /
> `seed-archinaut`. `packages-shared` gained an `isx86_64` gate (rar +
> cloud/devops toolbox) — the fleet's first aarch64 host exposed it.
> The HA power plugin + its sops secret are gated behind
> `printer.haPower.enable` (default off) so the host builds with no secret;
> sops-nix validates secrets at *build* time, so this gate is what lets the
> image build before provisioning. Uncommitted. **To enable the HA plug:** add
> archinaut's host age key to `.sops.yaml`, add `moonraker/secrets` to
> `secrets.yaml`, then set `printer.haPower.enable = true`.

## 8. Rollout

Phase ordering: (1) orion aarch64 binfmt, (2) resolve §6a extras (A or B) +
`klipper-host` module + ustreamer + moonraker settings, (3) `archinaut` host +
build SD image, (4) flash + first boot wired, (5) provision sops key → seed
config (rsync) + WiFi, (6) verify per service then join autoUpgrade. Old Debian
SD card kept as rollback throughout.

## 9. SD-card bootstrap (RPi3, aarch64, headless)

You don't pre-format or pre-partition the card. We build a NixOS **aarch64 SD
image** — it carries its own partition table (FAT firmware partition + ext4
root) and auto-expands the root on first boot. Any ≥8 GB card + a reader.

### What the flake provides (build-side)
- `orion`: `boot.binfmt.emulatedSystems = ["aarch64-linux"]` so it can build
  aarch64 under qemu.
- `nixosConfigurations.archinaut` imports
  `(modulesPath + "/installer/sd-card/sd-image-aarch64.nix")` →
  `config.system.build.sdImage` (extlinux + `ubootRaspberryPi3_64bit` +
  RPi firmware; `hardware.enableRedistributableFirmware = true` for later WiFi).
- Baked into the image: hostname `archinaut`, `erik` user + authorized SSH key,
  `openssh` (port 2222), tailscale, **wired DHCP** (→ router reservation `.225`).

### Steps (you run)
```bash
# 1. build the image (on orion, or from the laptop offloading to orion)
nix build .#nixosConfigurations.archinaut.config.system.build.sdImage \
  --builders 'ssh-ng://erik@192.168.10.220 aarch64-linux'   # orion binfmt
# result/sd-image/*.img.zst

# 2. find the card (NOT a partition — the whole disk), triple-check
lsblk

# 3. write it
zstd -dc result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M oflag=direct status=progress conv=fsync
sync

# 4. swap the card into the Pi (keep the old Debian SD = rollback), power on
# 5. headless boot → DHCP .225 → ssh erik@192.168.10.225 -p 2222
```
First boot expands the rootfs (may reboot once). Then: provision the sops age
key, `just seed-archinaut` (rsync repo → /var/lib/klipper), bring services up.

### Notes / caveats
- RPi3 ethernet is USB-attached 100 Mbit (`smsc95xx`, in mainline) — fine.
- WiFi (`brcmfmac`) is the **second** phase: needs SSID/PSK via sops, added once
  the host's sops key exists. Router reservation on the wifi MAC.
- `configDir = /var/lib/klipper`; `mutableConfig = true` so the rsync-seeded
  `printer.cfg` (+ `mainsail.cfg`, macros) persists and `SAVE_CONFIG` works.
- `boot.tmp.useTmpfs` (from `profile-base`) **must be forced off** on 1 GB RAM
  → `boot.tmp.useTmpfs = lib.mkForce false`; enable `zramSwap`.
