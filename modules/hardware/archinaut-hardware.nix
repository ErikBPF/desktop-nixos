_: {
  # Raspberry Pi 3 (BCM2837, aarch64, 1 GB RAM) — the BIQU B1 print host.
  # The bootloader is kernel-direct (GPU firmware loads the kernel, no u-boot) —
  # supplied by archinaut-kernel-direct, imported in the host's default.nix.
  flake.modules.nixos.archinaut-hardware = {lib, ...}: {
    nixpkgs.hostPlatform = "aarch64-linux";

    # RPi WiFi/BT (brcmfmac) firmware — needed for the phase-2 WiFi move.
    hardware.enableRedistributableFirmware = true;

    # 1 GB RAM: keep /tmp on disk (profile-base sets tmpfs — force off here) and
    # lean on zram instead of risking OOM during activation/large operations.
    boot.tmp.useTmpfs = lib.mkForce false;
    boot.tmp.cleanOnBoot = true;
    zramSwap.enable = true;

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
