_: {
  # Raspberry Pi 3 (BCM2837, aarch64, 1 GB RAM) — the BIQU B1 print host.
  # The SD-image bootloader/firmware (extlinux + u-boot-rpi3 + RPi firmware) is
  # supplied by sd-image-aarch64.nix, imported in the host's default.nix.
  flake.modules.nixos.archinaut-hardware = {lib, ...}: {
    nixpkgs.hostPlatform = "aarch64-linux";

    # RPi WiFi/BT (brcmfmac) firmware — needed for the phase-2 WiFi move.
    hardware.enableRedistributableFirmware = true;

    # 1 GB RAM: keep /tmp on disk (profile-base sets tmpfs — force off here) and
    # lean on zram instead of risking OOM during activation/large operations.
    boot.tmp.useTmpfs = lib.mkForce false;
    boot.tmp.cleanOnBoot = true;
    zramSwap.enable = true;

    # The Klipper MCU is wired to the GPIO UART (GPIO14/15), which is also
    # u-boot's serial console — with the printer powered, the MCU disrupts
    # u-boot and the Pi hangs before the kernel (boots with printer OFF, hangs
    # with it ON). CONFIG_BOOTDELAY=-2 (autoboot, no serial-stdin wait) was an
    # attempt at this; it does NOT fix the clash (the disruption is deeper than
    # the autoboot keypress). Kept only as a sane appliance default (no boot
    # wait). The real fix is kernel-direct boot — see
    # docs/proposals/2026-06-20-archinaut-kernel-direct-boot.md. Until then,
    # power-sequence: boot the Pi first, then power the printer.
    nixpkgs.overlays = [
      (_final: prev: {
        ubootRaspberryPi3_64bit = prev.ubootRaspberryPi3_64bit.override (o: {
          extraConfig =
            (o.extraConfig or "")
            + ''
              CONFIG_BOOTDELAY=-2
            '';
        });
      })
    ];

    networking.hostName = "archinaut";
    # Wired ethernet (USB smsc95xx) + WiFi both via DHCP.
    networking.useDHCP = lib.mkDefault true;

    # BOOTSTRAP WiFi — PSK baked plaintext so a fresh image joins headless (sops
    # can't decrypt before erik's age key is seeded; see migration plan). This
    # block is TEMPORARY: strip it before committing, and migrate the PSK to a
    # sops secret once the host is online and keyed.
    networking.wireless = {
      enable = true;
      networks."Que Wifi?".psk = "***REMOVED***";
    };
  };
}
