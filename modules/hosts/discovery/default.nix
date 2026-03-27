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
      m.nixos.nix-cache
      m.nixos.first-boot
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
      };
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;

    boot.loader = {
      grub = {
        enable = true;
        device = "/dev/sda";
        configurationLimit = 3;
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
