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
      };
    };

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

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#discovery";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "03:30";
    };
  };
}
