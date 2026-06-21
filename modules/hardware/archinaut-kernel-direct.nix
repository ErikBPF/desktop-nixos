_: {
  # Kernel-direct boot for the archinaut RPi3 (bcm2837) — drops u-boot.
  #
  # WHY: the Klipper MCU is wired to the GPIO UART (GPIO14/15), which is also
  # u-boot's serial console. With the printer powered, the MCU drives those
  # lines and u-boot hangs before the kernel. Raspberry Pi OS never had this
  # because it has NO u-boot stage — the GPU firmware loads the kernel directly.
  # This module reproduces that: the GPU firmware reads config.txt and loads the
  # mainline kernel + initrd straight from the FAT firmware partition.
  # See docs/proposals/2026-06-20-archinaut-kernel-direct-boot.md.
  #
  # Hosts that import this MUST import the base installer/sd-card/sd-image.nix
  # (NOT sd-image-aarch64.nix, which hardcodes u-boot + extlinux).
  flake.modules.nixos.archinaut-kernel-direct = {
    config,
    lib,
    pkgs,
    ...
  }: let
    fw = "${pkgs.raspberrypifw}/share/raspberrypi/boot";

    # The board is a Raspberry Pi 3 Model B PLUS (LAN7515 → lan78xx Gigabit +
    # USB2514 hub), so the matching mainline DTB is bcm2837-rpi-3-b-plus.dtb.
    # Use the MAINLINE kernel's own DTB, NOT the foundation one from raspberrypifw
    # (bcm2710-*): the pure-mainline kernel's dwc2/lan78xx nodes only match their
    # own DTB. The foundation DTB boots but leaves the whole USB tree (DWC2 → hub →
    # ethernet + webcam) dead; the plain 3B DTB brings USB up but not the 3B+
    # ethernet. This is the DTB the old u-boot/extlinux path loaded.
    dtb = "bcm2837-rpi-3-b-plus.dtb";
    kernelDtb = "${config.boot.kernelPackages.kernel}/dtbs/broadcom/${dtb}";

    configTxt = pkgs.writeText "config.txt" ''
      arm_64bit=1
      enable_uart=1
      core_freq=250
      avoid_warnings=1
      kernel=Image
      initramfs initrd followkernel
      device_tree=${dtb}
    '';

    # Shell that lays down the complete kernel-direct boot set into `dest`.
    # `toplevel` is a shell expression yielding the system toplevel path:
    #   - build time (populateFirmwareCommands): the literal store path
    #   - switch time (installHook): "$1"
    mkFirmware = {
      dest,
      toplevel,
    }: ''
      install -m0644 ${fw}/bootcode.bin ${dest}/bootcode.bin
      install -m0644 ${fw}/start.elf    ${dest}/start.elf
      install -m0644 ${fw}/fixup.dat    ${dest}/fixup.dat
      install -m0644 ${kernelDtb}       ${dest}/${dtb}
      install -m0644 ${configTxt}       ${dest}/config.txt
      install -m0644 ${toplevel}/kernel ${dest}/Image
      install -m0644 ${toplevel}/initrd ${dest}/initrd
      echo "$(cat ${toplevel}/kernel-params) init=${toplevel}/init" > ${dest}/cmdline.txt
    '';

    installHook = pkgs.writeShellScript "archinaut-kernel-direct-install" ''
      set -euo pipefail
      export PATH=${lib.makeBinPath [pkgs.coreutils pkgs.util-linux]}:$PATH

      # The GPU firmware and this hook share the FAT partition; it must be the
      # real mount, not the empty mountpoint on root (else the kernel never
      # updates and the Pi silently boots a stale generation).
      if ! mountpoint -q /boot/firmware; then
        mount /boot/firmware
      fi

      ${mkFirmware {
        dest = "/boot/firmware";
        toplevel = "\"$1\"";
      }}
      sync
    '';
  in {
    # No u-boot, no extlinux: the GPU firmware is the only bootloader stage.
    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.generic-extlinux-compatible.enable = lib.mkForce false;
    boot.loader.external = {
      enable = true;
      inherit installHook;
    };

    # No serial console on the cmdline — the GPIO UART belongs to the Klipper
    # MCU (klipper owns /dev/ttyS1). tty0 = HDMI for boot debug. rootwait covers
    # slow SD enumeration.
    boot.kernelParams = [
      "console=tty0"
      "rootwait"
    ];

    # Mount the FAT firmware partition (sd-image.nix defaults to noauto/nofail —
    # we need it mounted so the install hook writes to the real partition).
    fileSystems."/boot/firmware".options = lib.mkForce ["nofail"];

    sdImage = {
      # kernel (~60M) + initrd (~28M) + firmware blobs + headroom. Default 30M
      # cannot hold the kernel; the GPU firmware reads only this FAT partition.
      firmwareSize = 256;

      populateFirmwareCommands = mkFirmware {
        dest = "firmware";
        toplevel = "${config.system.build.toplevel}";
      };

      # No extlinux to populate; the boot set lives on the FAT partition. Keep a
      # /boot mountpoint present for the firmware mount.
      populateRootCommands = ''
        mkdir -p ./files/boot
      '';
    };
  };
}
