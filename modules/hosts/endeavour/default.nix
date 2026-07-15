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
      m.nixos.laptop-syncthing
      m.nixos.laptop-appimage
      m.nixos.endeavour-ampagent
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.kepler-nfs
      m.nixos.btrfs-snapshots
      m.nixos.endeavour-home-backup
      m.nixos.sccache-client
      m.nixos.netbird-client
    ];

    home-manager.users.${config.username} = {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.laptop-ssh
      ];
      inherit (config) colorScheme;

      wayland.windowManager.hyprland.settings.monitor = [
        {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = 1;
        }
        {
          output = "eDP-1";
          mode = "preferred";
          position = "1592x1680";
          scale = 1.25;
        }
        {
          output = "desc:Samsung Electric Company QBQ90 0x01000E00";
          mode = "2560x1440";
          position = "1080x240";
          scale = 1;
          bitdepth = 10;
        }
        {
          output = "desc:Samsung Electric Company C27F390 HX5MB00876";
          mode = "1920x1080";
          position = "0x0";
          scale = 1;
          transform = 1;
        }
        {
          output = "desc:Samsung Electric Company C27F390 HX5MB00881";
          mode = "1920x1080";
          position = "3640x0";
          scale = 1;
          transform = 3;
        }
      ];

      wayland.windowManager.hyprland.settings.workspace_rule = let
        qbq = "desc:Samsung Electric Company QBQ90 0x01000E00";
        c1 = "desc:Samsung Electric Company C27F390 HX5MB00876";
        c2 = "desc:Samsung Electric Company C27F390 HX5MB00881";
      in [
        {
          workspace = "1";
          monitor = qbq;
          default = true;
        }
        {
          workspace = "2";
          monitor = qbq;
        }
        {
          workspace = "3";
          monitor = qbq;
        }
        {
          workspace = "4";
          monitor = qbq;
        }
        {
          workspace = "5";
          monitor = qbq;
        }
        {
          workspace = "6";
          monitor = qbq;
        }
        {
          workspace = "7";
          monitor = qbq;
        }
        {
          workspace = "8";
          monitor = qbq;
        }
        {
          workspace = "9";
          monitor = qbq;
        }
        {
          workspace = "10";
          monitor = c1;
        }
        {
          workspace = "11";
          monitor = c2;
        }
        {
          workspace = "12";
          monitor = "eDP-1";
        }
      ];
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
    programs.sccacheClient.enable = true;
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };
    modules.security.tor-monitor.enable = true;
    modules.networking.netbird-client.enable = true;
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
