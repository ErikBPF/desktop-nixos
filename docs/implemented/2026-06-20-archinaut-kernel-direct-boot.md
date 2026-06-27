# RFC: archinaut kernel-direct boot (drop u-boot) for the Klipper MCU UART

**Status:** ✅ IMPLEMENTED (2026-06-21) · **Host:** `archinaut` (RPi 3 **Model B+** / bcm2837) · **Date:** 2026-06-20

> **Outcome (2026-06-21).** Deployed + cold-boot validated: the Pi boots
> kernel-direct (no u-boot) with the printer powered ON, klippy reaches `ready`
> unattended. Power-sequencing retired. Key deltas from the plan below, learned
> during bring-up (the rest of this RFC is the original proposal, kept for
> record):
> - Board is a **Pi 3 Model B+** → DTB must be the **mainline kernel's**
>   `bcm2837-rpi-3-b-plus.dtb` (NOT the foundation `bcm2710-*` from
>   raspberrypifw, which leaves USB/ethernet dead; NOT the plain 3B DTB).
> - MCU serial is **`/dev/ttyS1`** under that DTB (mini-UART; `/dev/ttyS0` is a
>   phantom port — see `klipper-biqu` printer.cfg).
> - Module `archinaut-kernel-direct` carries: `boot.loader.external` install
>   hook (atomic .tmp→rename), 256 M firmware sdImage, `firmwareSize = 256`.
> - klipper-host adds a **thermal-zone preStart wait** (bcm2835_thermal binds
>   late) and a **`klipper-mcu-recover`** oneshot (the PSU-powered MCU enters
>   shutdown on host reboot → one FIRMWARE_RESTART after boot).
> - DTB-name and `firmwarePartitionSize` notes in the plan below were corrected:
>   the option is `firmwareSize` (MiB); the DTB is the 3B+ one above.

## Problem

The Klipper MCU is wired to the Pi's **GPIO UART (GPIO14/15)** — the printer's
mainboard has no USB, only GPIO serial. That UART is also **u-boot's serial
console**. With the printer powered, the MCU drives those lines and u-boot hangs
during boot (autoboot interrupt / serial init) — **the Pi never reaches the
kernel**. Proven empirically:

- Boots fine with the **printer OFF**; hangs with it **ON**.
- `console=ttyAMA0`/`ttyS0` removed from the kernel cmdline → still hangs
  (problem is pre-kernel, in u-boot).
- u-boot `CONFIG_BOOTDELAY=-2` (autoboot, ignore serial stdin) → **still hangs**
  (disruption is deeper than the autoboot keypress).

The current NixOS generic `sd-image-aarch64` boots via `u-boot-rpi3.bin`.
Raspberry Pi OS never had this problem because it has **no u-boot stage** — the
GPU firmware loads the kernel directly.

## Why the easy fixes don't apply

- **raspberry-pi-nix** (which defaults to kernel-direct, `uboot.enable = false`)
  only supports **bcm2711 (Pi4)** and **bcm2712 (Pi5)** — **no Pi3/bcm2837**.
- **u-boot silent console** — risks a console-less u-boot that's unrecoverable
  without a card pull; uncertain it even helps (MCU disrupts serial init).

## Interim (in effect now)

**Power-sequencing**: boot the Pi first, then power the printer. The MCU only
clashes with u-boot *during* boot; once Linux is up, klipper owns `/dev/ttyS1`
fine (klippy reaches `ready`, Mainsail serves, MCU online). `system.autoUpgrade`
has `allowReboot = false`, so unattended upgrades never reboot — only **manual**
reboots need the sequence.

## Proposed: kernel-direct boot

Have the RPi GPU firmware load the Linux kernel directly (as Raspberry Pi OS
does), eliminating u-boot and its serial console entirely. `config.txt`:

```
kernel=<Image>
initramfs <initrd> followkernel
# device_tree auto-loaded: bcm2837-rpi-3-b.dtb
```
plus `cmdline.txt` carrying the kernel params (`init=…`, `root=…`,
`console=tty0` — **no serial console**).

## Blockers / scope (why this is a project, not a tweak)

1. **Firmware partition too small.** Kernel **60M** + initrd **28M** = **88M**,
   but the FAT FIRMWARE partition is **30M (6.3M free)**. The GPU firmware reads
   only FAT, so both must live there. → rebuild the SD image with
   `sdImage.firmwarePartitionSize` ≈ 256M. **Requires a reflash.**
2. **No built-in bootloader backend.** NixOS has no firmware-direct boot
   installer for the generic Pi3 (that machinery is exactly what raspberry-pi-nix
   provides for Pi4/5). We must write a custom `boot.loader` backend whose
   activation script copies the current generation's kernel+initrd to the FAT
   partition and regenerates `config.txt`/`cmdline.txt` on every
   `nixos-rebuild switch`.
3. **Generation rollback.** The GPU firmware loads one fixed kernel from
   `config.txt` — no extlinux generation menu. Either accept single-generation
   (lose rollback) or reimplement a switcher (e.g. `os_prefix`/multiple
   `config.txt` includes).
4. **Per-switch cost.** 88M kernel+initrd copied to FAT on each generation.
5. Full **rebuild + reflash + re-seed** cycle, plus several debug iterations
   (cmdline/DTB/root-device specifics on the Pi3).

## Recommendation

Run on **power-sequencing** now (printer is fully functional). Implement
kernel-direct deliberately as its own work item: prototype the firmware-direct
`boot.loader` backend + enlarged-firmware sdImage on a scratch build, validate
boot-with-printer-on, then reflash `archinaut`. Keep the old SD as rollback.

## Implementation plan (fresh-session-ready)

A new session can execute from here without this session's context. Read this
section + the "What's already in place" list below.

### Repo context (dendritic flake — orient first)

- `flake.nix` = `flake-parts.mkFlake` + `import-tree ./modules`. Every `.nix`
  under `modules/` is auto-imported; **new files must be `git add`ed before any
  `nix` eval sees them** (else "attribute missing").
- archinaut host: `modules/hosts/archinaut/default.nix` (imports
  `sd-image-aarch64.nix` + profiles + `archinaut-hardware` + `klipper-host`).
- hardware aspect: `modules/hardware/archinaut-hardware.nix` (hostPlatform,
  DHCP, wifi bootstrap, the `bootdelay=-2` u-boot overlay to **remove**).
- rescue host: `modules/hosts/archinaut-base/default.nix` (use it to prototype —
  it has no klipper stack, faster to iterate; same hardware module).
- Build: `just build-archinaut-sd` (aarch64 on orion `192.168.10.220` via binfmt;
  orion LAN is firewalled to ICMP — trust SSH `:2222`, not ping). Deploy:
  `just switch-archinaut` (targets wired `.187`). Flash: see migration-plan.md.

### Chosen approach

**`boot.loader.external` + a custom sdImage** (no u-boot, no extlinux). The RPi
GPU firmware reads `config.txt` and loads the kernel directly — exactly how
Raspberry Pi OS boots, and what **raspberry-pi-nix does for Pi4/5**. We adapt
that pattern to **bcm2837**.

> **Prior art to read & adapt:** `nix-community/raspberry-pi-nix` —
> `rpi/sd-image.nix` (firmware-partition population) and its bootloader/
> installer logic. It's Pi4/5-only, but the Pi3 differences are just the
> firmware blob names + DTB (`bcm2837-rpi-3-b.dtb`) + `start.elf`/`bootcode.bin`
> (Pi3 uses the 32-bit-named blobs with `arm_64bit=1`).

Start **single-generation** (no rollback menu — the old SD is the rollback).
Add a generation switcher later only if wanted.

### Pieces to build

1. **Larger firmware partition.** New module/override for archinaut's host:
   `sdImage.firmwarePartitionSize = 256 * 1024 * 1024;` (kernel 60M + initrd 28M
   + firmware blobs + headroom). **Stop importing
   `installer/sd-card/sd-image-aarch64.nix`** (it hardcodes u-boot); import the
   base `installer/sd-card/sd-image.nix` instead and supply our own
   `sdImage.populateFirmwareCommands`.
2. **`populateFirmwareCommands`** writes to the FAT firmware dir:
   - RPi GPU firmware blobs from `pkgs.raspberrypifw` (`bootcode.bin`,
     `start.elf`, `fixup.dat`, and `start4.elf`/etc not needed for Pi3).
   - `bcm2837-rpi-3-b.dtb` (from `pkgs.raspberrypifw` or the kernel's
     `${config.boot.kernelPackages.kernel}/dtbs/broadcom/`).
   - `config.txt` (see template) + `cmdline.txt`.
   - The kernel `Image` and `initrd` (copied from the current toplevel).
3. **`config.txt`** (kernel-direct):
   ```
   arm_64bit=1
   enable_uart=1            # keep; harmless, no u-boot console now
   core_freq=250            # keep — stabilises the mini-UART (ttyS1) for klipper
   kernel=Image
   initramfs initrd followkernel
   device_tree=bcm2837-rpi-3-b.dtb
   # NO dtoverlay=disable-bt (breaks nothing now, but unneeded — klipper uses ttyS1)
   ```
4. **`cmdline.txt`** (single line, NO serial console):
   ```
   console=tty0 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait init=<toplevel>/init loglevel=7
   ```
   (use the NIXOS_SD partition; `root=/dev/disk/by-label/NIXOS_SD` is more robust
   than `mmcblk0p2`.)
5. **`boot.loader`**: disable the extlinux/u-boot loader; set
   `boot.loader.external.enable = true` + an `installHook` that, on every
   `nixos-rebuild switch/boot`, copies the new generation's kernel+initrd to
   `/boot/firmware` and rewrites `cmdline.txt` (`init=<new-toplevel>/init`).
   Mount the FAT partition at `/boot/firmware` (fileSystems entry) so the hook
   and the GPU firmware share it.
6. **Remove** the `bootdelay=-2` u-boot overlay from `archinaut-hardware.nix`
   (u-boot is gone). Keep the serial-console-free cmdline.

### Spikes to resolve FIRST (before a full archinaut reflash)

Prototype on `archinaut-base` + a **spare SD** (do NOT touch the working
archinaut card until proven; keep it + the Debian SD as rollback):

- **S1:** Does RPi3 GPU firmware kernel-direct-boot a mainline arm64 `Image` +
  initrd via `config.txt` on `pkgs.raspberrypifw` blobs? (Expected yes.)
- **S2:** Correct DTB source/name and whether `device_tree=` is needed vs
  firmware auto-load.
- **S3:** `boot.loader.external` installHook shape on this NixOS version (signature,
  how it receives the toplevel, how to find kernel/initrd paths).
- **S4:** root= device reliability (by-label NIXOS_SD vs mmcblk0p2; rootwait).
- **S5:** Confirms the printer-ON boot now succeeds (the whole point) — test with
  the printer powered on the spare rig.

### Steps

1. Create `modules/hosts/archinaut-base/` variant (or a `_kernel-direct.nix`
   aspect) implementing pieces 1–5; `git add`.
2. `just lint && just fmt-check`; eval
   `.#nixosConfigurations.archinaut-base.config.system.build.sdImage.drvPath`.
3. `nix build .#nixosConfigurations.archinaut-base.config.system.build.sdImage`
   on orion; flash a **spare** SD.
4. Boot the spare on the Pi3 **with a UART peripheral / printer attached** →
   resolve S1–S5 (HDMI console invaluable here).
5. Once green, fold the approach into the real `archinaut` host, rebuild, flash
   the archinaut card (back up `/var/lib/klipper` first or just re-seed after),
   boot, `just seed-archinaut`, verify klippy `ready` **without** power-sequencing.
6. Remove the `bootdelay=-2` overlay; update migration-plan.md (drop the
   power-sequencing caveat); commit.

### Definition of done

Pi3 boots to a `ready` klipper **with the printer already powered on** (no
power-sequencing), `/dev/ttyS1` owned by klipper, no u-boot in the boot chain,
and `nixos-rebuild switch` correctly updates the boot partition.

### Risks

- FAT firmware partition exhaustion if initrd grows — size with headroom (256M).
- Losing generation rollback (mitigated by the old SD; revisit if needed).
- Mainline-kernel/RPi-firmware DTB mismatches — the main debug surface (S2).

## What's already in place (so this stands alone)

- `printer.cfg [mcu] serial = /dev/ttyS1` (the clocked mini-UART; `ttyS0` is a
  dead placeholder, `ttyAMA0`/PL011 needs `disable-bt` which itself breaks
  u-boot). In the `klipper-biqu` repo.
- `archinaut-hardware.nix` carries a `ubootRaspberryPi3_64bit` overlay with
  `CONFIG_BOOTDELAY=-2` — harmless (faster unattended boot) but does **not**
  resolve the MCU clash; revisit/remove when kernel-direct lands.
- klipper extras vendored (autotune + gcode_shell_command); KAMP + mainsail.cfg
  recovered into the repo working tree.
