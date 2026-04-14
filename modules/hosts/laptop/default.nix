{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  monitors = [
    {
      name = "eDP-1";
      resolution = "1920x1080";
      refreshRate = 60;
      position = "1592x1680";
      scale = 1.25;
    }
    {
      name = "desc:Samsung Electric Company QBQ90 0x01000E00";
      resolution = "2560x1440";
      refreshRate = 60;
      position = "1080x240";
    }
    {
      name = "desc:Samsung Electric Company C27F390 HX5MB00876";
      resolution = "1920x1080";
      refreshRate = 60;
      position = "0x0";
    }
    {
      name = "desc:Samsung Electric Company C27F390 HX5MB00881";
      resolution = "1920x1080";
      refreshRate = 60;
      position = "3640x0";
    }
  ];
  workspaces = [
    {
      id = 1;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
      default = true;
    }
    {
      id = 2;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 3;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 4;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 5;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 6;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 7;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 8;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 9;
      monitor = "desc:Samsung Electric Company QBQ90 0x01000E00";
    }
    {
      id = 10;
      monitor = "desc:Samsung Electric Company C27F390 HX5MB00876";
    }
    {
      id = 11;
      monitor = "desc:Samsung Electric Company C27F390 HX5MB00881";
    }
    {
      id = 12;
      monitor = "eDP-1";
    }
  ];

  configurations.nixos.laptop.module = {
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
      m.nixos.laptop-hardware
      m.nixos.laptop-networking
      m.nixos.laptop-syncthing
      m.nixos.laptop-appimage
      m.nixos.laptop-ampagent
      m.nixos.first-boot
      m.nixos.alloy
      m.nixos.kepler-nfs
    ];

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${config.username} = {
        imports = [
          inputs.nix-colors.homeManagerModules.default
          inputs.sops-nix.homeManagerModules.sops
          m.home.profile-base
          m.home.profile-desktop
          m.home.laptop-ssh
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
        inherit (config) colorScheme;

        wayland.windowManager.hyprland.settings.monitor = [
          ",preferred,auto,1"
          "eDP-1,preferred,1592x1680,1.25"
          "desc:Samsung Electric Company QBQ90 0x01000E00,2560x1440,1080x240,1,bitdepth,10"
          "desc:Samsung Electric Company C27F390 HX5MB00876,1920x1080,0x0,1,transform,1"
          "desc:Samsung Electric Company C27F390 HX5MB00881,1920x1080,3640x0,1,transform,3"
        ];

        wayland.windowManager.hyprland.extraConfig = ''
          cursor {
            no_hardware_cursors = true
          }
          workspace = 1, monitor:desc:Samsung Electric Company QBQ90 0x01000E00, default:true
          workspace = 2, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 3, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 4, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 5, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 6, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 7, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 8, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 9, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
          workspace = 10, monitor:desc:Samsung Electric Company C27F390 HX5MB00876
          workspace = 11, monitor:desc:Samsung Electric Company C27F390 HX5MB00881
          workspace = 12, monitor:eDP-1
        '';
      };
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
          useOSProber = true;
          timeoutStyle = "menu";
          configurationLimit = 3;
        };
        timeout = 1;
      };
    };

    services.btrfs.autoScrub.enable = true;

    # Offload heavy builds to Orion (Ryzen 9 5950X, 32t, 62GB RAM)
    nix.distributedBuildsOrion.enable = true;

    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };

    modules.security.tor-monitor.enable = true;

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#laptop";
      operation = "switch";
      flags = ["--show-trace"];
      allowReboot = false;
      dates = "05:00";
    };

    services.openssh.enable = true;
  };
}
