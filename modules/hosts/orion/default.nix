{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.orion.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      inputs.jovian.nixosModules.default
      m.nixos.profile-base
      m.nixos.orion-hardware
      m.nixos.orion-networking
      m.nixos.orion-syncthing
      m.nixos.orion-containers
      m.nixos.first-boot
      m.nixos.orion-jovian
      m.nixos.orion-sunshine
      m.nixos.hyprland
      m.nixos.audio
      m.nixos.bluetooth
      m.nixos.xdg-portal
      m.nixos.fonts
      m.nixos.alloy
      m.nixos.nix-cache
      m.nixos.kepler-nfs
      m.nixos.orchestration
      m.nixos.orion-compose
    ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${config.username} = {
        imports = [
          inputs.nix-colors.homeManagerModules.default
          inputs.sops-nix.homeManagerModules.sops
          m.home.profile-base
          m.home.orion-ssh
          m.home.hyprland
          m.home.fonts
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
        inherit (config) colorScheme;
      };
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = true;
    boot.kernelPackages = pkgs.linuxPackages_latest;

    boot = {
      kernelParams = ["nohibernate"];
      loader = {
        efi.canTouchEfiVariables = true;
        grub = {
          device = "nodev";
          efiSupport = true;
          enable = true;
          useOSProber = false;
          timeoutStyle = "menu";
          configurationLimit = 10;
        };
        timeout = 3;
      };
    };

    services.btrfs.autoScrub.enable = true;

    # Allow laptop's nix-builder root key to trigger builds via ssh-ng
    users.users.${config.username}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop"
    ];

    zramSwap = {
      enable = true;
      algorithm = "zstd";
    };

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#orion";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };

    services.openssh.enable = true;
  };
}
