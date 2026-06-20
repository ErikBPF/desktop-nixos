# RFC: archinaut kernel-direct boot (drop u-boot) for the Klipper MCU UART

**Status:** proposed · **Host:** `archinaut` (RPi3 / bcm2837) · **Date:** 2026-06-20

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

## What's already in place (so this stands alone)

- `printer.cfg [mcu] serial = /dev/ttyS1` (the clocked mini-UART; `ttyS0` is a
  dead placeholder, `ttyAMA0`/PL011 needs `disable-bt` which itself breaks
  u-boot). In the `klipper-biqu` repo.
- `archinaut-hardware.nix` carries a `ubootRaspberryPi3_64bit` overlay with
  `CONFIG_BOOTDELAY=-2` — harmless (faster unattended boot) but does **not**
  resolve the MCU clash; revisit/remove when kernel-direct lands.
- klipper extras vendored (autotune + gcode_shell_command); KAMP + mainsail.cfg
  recovered into the repo working tree.
