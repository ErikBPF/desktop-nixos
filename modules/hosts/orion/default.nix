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
      m.nixos.profile-base
      m.nixos.orion-hardware
      m.nixos.orion-networking
      m.nixos.orion-syncthing
      m.nixos.first-boot
    ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${config.username} = {
        imports = [
          inputs.sops-nix.homeManagerModules.sops
          m.home.profile-base
          m.home.orion-ssh
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
      dates = "04:00";
    };

    services.openssh.enable = true;
  };
}
