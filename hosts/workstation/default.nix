{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  modulesPath,
  ...
} @ args: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.home-manager.nixosModules.default
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    (import ../../modules/nixos/default.nix inputs)
    ./hardware-configuration.nix
    ../../modules/users/erik.nix
    ./disk-config.nix

    ../common/global.nix
    # ./syncthing.nix
  ];
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
      };
      timeout = 300;
    };
    kernelPackages = pkgs.linuxPackages_zen;
  };

  services.btrfs.autoScrub.enable = true;
  nix.settings.auto-optimise-store = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  systemd = {
    slices."nix-daemon".sliceConfig = {
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "95%";
    };
    services."nix-daemon" = {
      serviceConfig = {
        Slice = "nix-daemon.slice";
        OOMScoreAdjust = 1000;
      };
    };
  };

  # system.autoUpgrade = {
  #   enable = true;
  #   flake = "github:ErikBPF/desktop-nixos#workstation";
  #   operation = "boot";
  #   randomizedDelaySec = "45min";
  #   allowReboot = false;
  #   dates = "02:00";
  # };

  services.openssh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "backup";
  home-manager.extraSpecialArgs = {inherit inputs outputs;};

  home-manager.users.erik = {
    imports = [
      ../../home/erik
      inputs.nix-colors.homeManagerModules.default
      inputs.sops-nix.homeManagerModules.sops
      ../../modules/home-manager/default.nix
    ];
    colorScheme = inputs.nix-colors.colorSchemes.tokyo-night-dark;
  };

  system.stateVersion = "25.05";
}
