{self, ...}: {
  # Raspberry Pi 3 (BCM2837, aarch64, 1 GB RAM) — the BIQU B1 print host.
  # The bootloader is kernel-direct (GPU firmware loads the kernel, no u-boot) —
  # supplied by archinaut-kernel-direct, imported in the host's default.nix.
  flake.modules.nixos.archinaut-hardware = {
    config,
    lib,
    ...
  }: {
    nixpkgs.hostPlatform = "aarch64-linux";

    # RPi WiFi/BT (brcmfmac) firmware — needed for the phase-2 WiFi move.
    hardware.enableRedistributableFirmware = true;

    # 1 GB RAM: keep /tmp on disk (profile-base sets tmpfs — force off here) and
    # lean on zram instead of risking OOM during activation/large operations.
    boot.tmp.useTmpfs = lib.mkForce false;
    boot.tmp.cleanOnBoot = true;
    zramSwap.enable = true;

    networking.hostName = "archinaut";
    # Wired ethernet (USB lan78xx on the 3B+) + WiFi both via DHCP. Wired is the
    # primary path; WiFi is the headless fallback.
    networking.useDHCP = lib.mkDefault true;

    # WiFi PSK comes from sops (varname=value secretsFile format), referenced by
    # `ext:` so it never lands in the world-readable Nix store. A fresh reflash
    # can't decrypt this until its host key is re-keyed in .sops.yaml (the host
    # boots on WIRED first, then sops + WiFi come up after the re-key + deploy).
    sops.secrets."wifi_secrets".sopsFile = self + "/secrets/sops/secrets.yaml";
    networking.wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi_secrets".path;
      networks."Que Wifi?".pskRaw = "ext:psk_quewifi";
    };
  };
}
