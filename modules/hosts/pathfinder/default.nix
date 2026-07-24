{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
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
      m.nixos.systemd-boot-counting
      m.nixos.pathfinder-hardware
      m.nixos.pathfinder-networking
      m.nixos.pathfinder-syncthing
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.kepler-nfs
      m.nixos.btrfs-snapshots
    ];

    home-manager.users.${config.username} = {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.monitor-layout-pathfinder
        m.home.pathfinder-ssh
      ];
      inherit (config) colorScheme;
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;
    boot.kernelPackages = pkgs.linuxPackages_zen;

    # Bootloader: systemd-boot + boot-counting via the systemd-boot-counting
    # module imported above (it force-disables GRUB and adds panic/watchdog
    # wiring).
    boot = {
      kernelParams = ["nohibernate"];
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.configurationLimit = 3;
        timeout = 1;
      };
    };

    services.btrfs.autoScrub.enable = true;

    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };

    modules.security.tor-monitor.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "git+https://github.com/ErikBPF/desktop-nixos?ref=main#pathfinder";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
      # Stagger off the 05:00 herd (orion cache settles by 04:30).
      randomizedDelaySec = "900";
    };

    services.openssh.enable = true;
  };
}
