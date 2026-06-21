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
    # Wired ethernet (USB lan78xx on the 3B+) via DHCP — the production path.
    # Remote access also runs over tailscale, so WiFi is not needed as a fallback
    # for now (and the plaintext bootstrap PSK has been removed from config/git).
    networking.useDHCP = lib.mkDefault true;

    # WiFi disabled — see migration-plan Step 9. The sops-backed config below is
    # correct per the NixOS docs (secretsFile + pskRaw=ext:, PSK never in the Nix
    # store) BUT wpa_supplicant's file ext_password backend returns "No PSK found
    # from external storage" on this build (persists across reboot; not an
    # ordering or newline issue). Resolving that — or switching to a working
    # secret path — is the Step-9 WiFi task. The hex PSK is parked in sops as
    # `wifi_secrets` ready for then. Until then: wired + tailscale.
    #
    # sops.secrets."wifi_secrets".sopsFile = self + "/secrets/sops/secrets.yaml";
    # networking.wireless = {
    #   enable = true;
    #   secretsFile = config.sops.secrets."wifi_secrets".path;
    #   networks."Que Wifi?".pskRaw = "ext:psk_quewifi";
    # };
  };
}
