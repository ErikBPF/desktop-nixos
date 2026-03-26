{
  config,
  inputs,
  self,
  ...
}: let
  overlays = import ../../overlays {inherit inputs;};
in {
  monitors = [
    {
      name = "DP-1";
      resolution = "1920x1080";
      refreshRate = 60;
      position = "0x0";
    }
  ];
  workspaces = [
    {
      id = 1;
      monitor = "DP-1";
      default = true;
    }
    {
      id = 2;
      monitor = "DP-1";
    }
    {
      id = 3;
      monitor = "DP-1";
    }
    {
      id = 4;
      monitor = "DP-1";
    }
    {
      id = 5;
      monitor = "DP-1";
    }
  ];

  configurations.nixos.pathfinder.module = {
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      (import ../../modules/_nixos/default.nix inputs)
      ../../hosts/common/global.nix
      ../../hosts/workstation/hardware-configuration.nix
      ../../modules/_users/erik.nix
      ../../hosts/workstation/disk-config.nix
      ../../hosts/workstation/syncthing.nix
    ];

    _module.args = {
      inherit inputs;
      outputs = {inherit overlays;};
      inherit (config) secrets;
    };

    # Enable system modules
    modules = {
      desktop.enable = true;
      dev.enable = true;
      graphics = {
        enable = true;
        driver = "nvidia";
      };
      security.tor-monitor.enable = true;
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

    networking = {
      hostName = "pathfinder";
      networkmanager.enable = true;
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = true;
        checkReversePath = "loose";
        allowedTCPPorts = [
          80
          443
          22000
        ];
        allowedUDPPorts = [21027];
      };
    };

    system.autoUpgrade = {
      enable = true;
      flake = "github:ErikBPF/desktop-nixos#pathfinder";
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

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      extraSpecialArgs = {
        inherit inputs;
        outputs = {inherit overlays;};
      };
      users.erik = {
        imports = [
          ../../home/erik
          inputs.nix-colors.homeManagerModules.default
          inputs.sops-nix.homeManagerModules.sops
          ../../modules/_home-manager/default.nix
        ];
        colorScheme = inputs.nix-colors.colorSchemes.tokyo-night-dark;
      };
    };
  };
}
