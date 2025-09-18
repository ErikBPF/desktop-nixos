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
    (import ../../modules/nixos/default.nix inputs)
    ./hardware-configuration.nix
    ../../modules/users/erik.nix
    ./disk-config.nix

    ../common/global.nix
    ../common/packages.nix
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
  };

  services.openssh.enable = true;

  inputs.sops-nix.nixosModules.sops = {
    secrets = {
      "syncthing/moon_id"  = {};
      "syncthing/archlinux_id" = {};
    };
  };

  services.syncthing = {
    overrideDevices = true;
    overrideFolders = true;
    configDir = "/home/erik/.config/syncthing";
    settings = {
      devices = {
        "Moon" = {
          id = builtins.readFile config.sops.secrets."syncthing/moon_id".path;
        };
        "archlinux" = {
          id = builtins.readFile config.sops.secrets."syncthing/archlinux_id".path;
        };
      };

      folders = {
        "ndykv-cjhly" = {
          label = "Downloads";
          path = "/home/erik/Downloads/";
          devices = [
            "Moon"
            "archlinux"
          ];
        };
      };
    };
  };

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
