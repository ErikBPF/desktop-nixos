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
    ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${config.username} = {
        imports = [
          inputs.sops-nix.homeManagerModules.sops
          m.home.profile-base
          m.home.discovery-ssh
        ];
        home = {
          inherit (config) username;
          homeDirectory = "/home/${config.username}";
          stateVersion = "25.11";
        };
        xdg = {
          enable = true;
          userDirs = {
            enable = true;
            createDirectories = true;
            setSessionVariables = true;
          };
        };
        programs.home-manager.enable = true;

        # NOTE: fuse-overlayfs storage.conf removed — discovery now uses rootful
        # Docker instead of rootless Podman. See modules/hosts/discovery/containers.nix.
      };
    };

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
        configurationLimit = 5;
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
