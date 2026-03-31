{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.kepler.module = {
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
      m.nixos.kepler-hardware
      m.nixos.kepler-networking
      m.nixos.kepler-syncthing
      m.nixos.kepler-nas
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
          m.home.kepler-ssh
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

    # ZFS hostId — generated from /etc/machine-id on live ISO (head -c 8 /etc/machine-id)
    networking.hostId = "cf7e11b5";

    # CUDA container toolkit for AI inference workloads
    hardware.nvidia-container-toolkit.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#kepler";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "04:00";
    };
  };
}
