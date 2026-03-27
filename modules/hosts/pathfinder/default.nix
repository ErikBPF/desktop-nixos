{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  monitors = [
    {
      name = "DP-1";
      resolution = "1920x1080";
      refreshRate = 60;
      position = "0x0";
    }
  ];
  workspaces = [
    {
      id = 1;
      monitor = "DP-1";
      default = true;
    }
    {
      id = 2;
      monitor = "DP-1";
    }
    {
      id = 3;
      monitor = "DP-1";
    }
    {
      id = 4;
      monitor = "DP-1";
    }
    {
      id = 5;
      monitor = "DP-1";
    }
  ];

  configurations.nixos.pathfinder.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-desktop
      m.nixos.pathfinder-hardware
      m.nixos.pathfinder-networking
      m.nixos.pathfinder-syncthing
    ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${config.username} = {
        imports = [
          inputs.nix-colors.homeManagerModules.default
          inputs.sops-nix.homeManagerModules.sops
          m.home.profile-base
          m.home.profile-desktop
          m.home.pathfinder-ssh
        ];
        home.username = config.username;
        home.homeDirectory = "/home/${config.username}";
        home.stateVersion = "25.11";
        home.enableNixpkgsReleaseCheck = false;
        xdg = {
          enable = true;
          userDirs = {
            enable = true;
            createDirectories = true;
          };
        };
        programs.home-manager.enable = true;
        colorScheme = config.colorScheme;
      };
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;
    boot.kernelPackages = pkgs.linuxPackages_zen;

    boot = {
      kernelParams = ["nohibernate"];
      tmp.cleanOnBoot = true;
      supportedFilesystems = ["ntfs"];
      loader = {
        efi.canTouchEfiVariables = true;
        grub = {
          device = "nodev";
          efiSupport = true;
          enable = true;
          useOSProber = true;
          timeoutStyle = "menu";
          configurationLimit = 3;
        };
        timeout = 1;
      };
    };

    services.btrfs.autoScrub.enable = true;
    nix.settings.auto-optimise-store = true;

    zramSwap = {
      enable = true;
      algorithm = "zstd";
    };

    modules.security.tor-monitor.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#pathfinder";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };

    services.openssh.enable = true;
  };
}
