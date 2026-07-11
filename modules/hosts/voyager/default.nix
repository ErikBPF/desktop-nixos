{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.voyager.module = {
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.profile-oci-guest
      m.nixos.voyager-hardware
      m.nixos.voyager-networking
      m.nixos.containers
      m.nixos.voyager-compose
      m.nixos.node-exporter
      m.nixos.first-boot
      # NetBird native relay (WP3, docs/proposals/2026-07-10-
      # netbird-selfhosted-overlay.md §4a/§6b). Registers services.netbirdRelay
      # but stays off: enable defaults to false and is not flipped on here
      # (Phase S/O are human-gated — see the implementation plan).
      m.nixos.netbird-relay
    ];

    # Rollback guard: offsite backups need SSH, Tailscale, and the receiver stack.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
    ];

    system.stateVersion = "25.11";
    # Oracle Always-Free x86 shape (VM.Standard.E2.1.Micro, 1 GB).
    # A1 (aarch64) capacity is scarce in sa-saopaulo-1, so voyager runs on the
    # x86 micro. The 1 GB micro can't kexec-install (OOMs), so it is provisioned
    # via nixos-infect on a stock Ubuntu cloud image.
    nixpkgs.hostPlatform = "x86_64-linux";

    # Oracle VM is ~1GB RAM. zram is intentionally disabled on this host; keep
    # /tmp off tmpfs so activation does not consume scarce RAM.
    zramSwap.enable = false;
    boot.tmp.useTmpfs = lib.mkForce false;
    boot.tmp.cleanOnBoot = true;

    # Oracle block volumes don't support SMART; smartd exits non-zero and
    # marks the system degraded. Disable it on this guest.
    services.smartd.enable = lib.mkForce false;

    virtualisation.vmVariant = {
      # Force legacy eth0 naming so the static config below lands on the real
      # interface. Without this, predictable naming yields ens3 and the IP is
      # configured on a nonexistent eth0 → guest unreachable on the tap.
      boot.kernelParams = ["net.ifnames=0"];

      networking = {
        defaultGateway = "10.88.0.1";
        firewall.interfaces.eth0.allowedTCPPorts = [8000];
        hostName = lib.mkForce "voyager-vm";
        interfaces.eth0.ipv4.addresses = [
          {
            address = "10.88.0.2";
            prefixLength = 24;
          }
        ];
        nameservers = ["1.1.1.1" "9.9.9.9"];
        useDHCP = lib.mkForce false;
      };
      # The VM validates boot + compose without joining the production tailnet.
      services.tailscale.enable = lib.mkForce false;

      virtualisation = {
        cores = 1;
        diskSize = 4096;
        qemu.networkingOptions = lib.mkForce [
          "-device virtio-net-pci,netdev=user.0,mac=52:54:00:88:00:02"
          "-netdev tap,id=user.0,ifname=voyager-vm-tap,script=no,downscript=no"
        ];
        graphics = false;
        memorySize = 1024;
        sharedDirectories.sops-age = {
          source = "/home/erik/.config/sops/age";
          target = "/home/erik/.config/sops/age";
          securityModel = "none";
        };
      };
    };
  };
}
