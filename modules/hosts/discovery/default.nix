{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.discovery.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.discovery-hardware
      m.nixos.discovery-networking
      m.nixos.discovery-syncthing
      m.nixos.discovery-haos
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.kepler-nfs
      m.nixos.discovery-containers
      m.nixos.discovery-compose
      m.nixos.discovery-hermes-agent
      m.nixos.power-desktop
      m.nixos.btrfs-snapshots
      m.nixos.homelab-iac-drift
      m.nixos.restic-tofu-state
    ];

    # Versioned backup of the tofu-state mirror onto vault (sdb), independent of
    # the primary SSD that holds the live state. Off-host copies go to orion +
    # kepler via Syncthing (discovery-syncthing tofu-state folder).
    services.resticTofuState.enable = true;

    # Drift detection for the homelab-iac repo (UniFi/Tailscale/Cloudflare/
    # AdGuard). Runs here because discovery is the 24/7 host with LAN + tailnet
    # reach to every provider and hosts the MinIO state backend it plans against.
    services.homelabIacDrift = {
      enable = true;
      repoPath = "/home/${config.username}/homelab-iac";
      user = config.username;
      ntfyUrl = "https://ntfy.homelab.pastelariadev.com/homelab-alerts";
    };

    # Rollback guard: docker runs the compose stacks, libvirtd runs HAOS.
    modules.upgradeHealthCheck.criticalUnits = [
      "sshd.service"
      "tailscaled.service"
      "docker.service"
      "libvirtd.service"
    ];

    # NOTE: fuse-overlayfs storage.conf removed — discovery now uses rootful
    # Docker instead of rootless Podman. See modules/hosts/discovery/containers.nix.
    home-manager.users.${config.username}.imports = [
      m.home.discovery-ssh
    ];

    # Lingering allows erik's systemd user session (and user services) to
    # survive after logout and start on boot without an interactive login.
    # Required for rootless Podman compose stacks to auto-start.
    users.users.${config.username}.linger = true;

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;

    boot.loader = {
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        useOSProber = false;
        configurationLimit = 3;
      };
    };

    boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 53;

    hardware.nvidia-container-toolkit.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#discovery";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };
  };
}
