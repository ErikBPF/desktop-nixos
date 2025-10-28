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
    ../common/global.nix
    ./hardware-configuration.nix
    ../../modules/users/erik.nix
    ./disk-config.nix
    ./syncthing.nix
  ];

  # Enable system modules
  modules = {
    desktop.enable = true;
    dev.enable = true;
    graphics = {
      enable = true;
      driver = "intel";
    };
  };
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
    kernelPackages = pkgs.linuxPackages_zen;
  };

  services.btrfs.autoScrub.enable = true;
  nix.settings.auto-optimise-store = true;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # systemd = {
  #   slices."nix-daemon".sliceConfig = {
  #     ManagedOOMMemoryPressure = "kill";
  #     ManagedOOMMemoryPressureLimit = "95%";
  #   };
  #   services."nix-daemon" = {
  #     serviceConfig = {
  #       Slice = "nix-daemon.slice";
  #       OOMScoreAdjust = 1000;
  #     };
  #   };
  # };

  networking = {
    hostName = "laptop";
    networkmanager.enable = true;
    networkmanager.dns = "systemd-resolved";
    firewall = {
      enable = true;
      checkReversePath = "loose"; # fixes connection issues with tailscale
      allowedTCPPorts = [22 80 443 22000];
      allowedUDPPorts = [21027];
    };
    # hosts = {
    #   "168.62.50.31" = [ "airflow-datalake-prd.nstech.com.br" ];
    # };
  };

  system.autoUpgrade = {
    enable = true;
    flake = "github:ErikBPF/desktop-nixos#laptop";
    operation = "switch";
    randomizedDelaySec = "45min";
    flags = [
      "--impure"
      "--show-trace"
    ];
    allowReboot = false;
    dates = "05:00";
  };

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
}
