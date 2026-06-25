{self, ...}: {
  # Raspberry Pi 3 (BCM2837, aarch64, 1 GB RAM) — the BIQU B1 print host.
  # The bootloader is kernel-direct (GPU firmware loads the kernel, no u-boot) —
  # supplied by archinaut-kernel-direct, imported in the host's default.nix.
  flake.modules.nixos.archinaut-hardware = {
    lib,
    config,
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

    # WiFi is the primary link now — the USB lan78xx wired NIC proved flaky.
    # NetworkManager manages both interfaces (matches laptop/pathfinder/orion):
    # the wired port auto-connects via NM's default DHCP profile and stays as a
    # fallback, while WiFi connects via the declarative profile below. NM runs
    # its own DHCP, so `networking.useDHCP` is intentionally left unset.
    #
    # The earlier WiFi attempt used wpa_supplicant's `ext:` file password backend
    # (networking.wireless.secretsFile + pskRaw="ext:…"), which returned "No PSK
    # found from external storage" on this build; nixpkgs has since removed the
    # `@var@`/environmentFile escape hatch, leaving NM as the reliable path.
    networking.networkmanager = {
      enable = true;
      dns = "systemd-resolved"; # profile-base enables resolved
      ensureProfiles = {
        # PSK never enters the Nix store: the raw 64-hex key lives in sops as
        # `wifi_secrets` (a single `psk_quewifi=<hex>` line) and is substituted
        # into the keyfile at activation via $psk_quewifi.
        environmentFiles = [config.sops.secrets."wifi_secrets".path];
        profiles.quewifi = {
          connection = {
            id = "Que Wifi?";
            type = "wifi";
            autoconnect = true;
          };
          wifi = {
            ssid = "Que Wifi?";
            mode = "infrastructure";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "$psk_quewifi";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };

    sops.secrets."wifi_secrets".sopsFile = self + "/secrets/sops/secrets.yaml";
  };
}
