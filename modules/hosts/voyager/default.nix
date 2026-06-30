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
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.voyager-hardware
      m.nixos.voyager-networking
      m.nixos.containers
      m.nixos.voyager-compose
      m.nixos.first-boot
    ];

    # Rollback guard: offsite backups need SSH, Tailscale, and the receiver stack.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
    ];

    system.stateVersion = "25.11";
    # Oracle Ampere A1 free-tier shape: aarch64, ample RAM (kexec install works,
    # unlike the 1 GB x86 micro). Closure is cross-built on Orion (binfmt).
    nixpkgs.hostPlatform = "aarch64-linux";

    # Oracle VM is ~1GB RAM. zram is intentionally disabled on this host; keep
    # /tmp off tmpfs so activation does not consume scarce RAM.
    zramSwap.enable = false;
    boot.tmp.useTmpfs = lib.mkForce false;
    boot.tmp.cleanOnBoot = true;

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
