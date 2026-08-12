{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.endeavour.module = {
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
      m.nixos.endeavour-hardware
      m.nixos.endeavour-networking
      m.nixos.endeavour-ubuntu-work
      m.nixos.laptop-syncthing
      m.nixos.first-boot
      m.nixos.pangolin-newt
      m.nixos.alloy
      m.nixos.kepler-nfs
      m.nixos.btrfs-snapshots
      m.nixos.endeavour-home-backup
      m.nixos.sccache-client
    ];

    home-manager.users.${config.username} = {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.monitor-layout-docked
      ];
      inherit (config) colorScheme;
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;
    boot.kernelPackages = pkgs.linuxPackages_zen;
    boot = {
      kernelParams = ["nohibernate"];
      supportedFilesystems = ["ntfs"];
      loader = {
        efi.canTouchEfiVariables = true;
        grub = {
          device = "nodev";
          efiSupport = true;
          enable = true;
          configurationLimit = 3;
        };
        timeout = 1;
      };
    };
    services.btrfs.autoScrub.enable = true;
    nix.distributedBuildsOrion.enable = true;
    nix.distributedBuildsKepler.enable = true;
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
    programs.sccacheClient.enable = true;
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };
    modules.security.tor-monitor.enable = true;
    system.autoUpgrade = {
      enable = true;
      flake = "git+https://github.com/ErikBPF/desktop-nixos?ref=main#endeavour";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
      randomizedDelaySec = "900";
    };
    services.openssh.enable = true;
  };
}
