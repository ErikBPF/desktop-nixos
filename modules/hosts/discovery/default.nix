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
      m.nixos.discovery-haos
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
          m.home.discovery-ssh
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

        # Rootless Podman on btrfs: native overlayfs in user namespaces
        # strips execute bits from files owned by uid 0 (e.g. ld-linux-x86-64.so.2
        # gets 711 instead of 755). fuse-overlayfs handles uid mapping in userspace
        # and preserves layer permissions correctly.
        home.file.".config/containers/storage.conf".text = ''
          [storage]
          driver = "overlay"

          [storage.options.overlay]
          mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs"
        '';
      };
    };

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;

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

    boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 53;

    hardware.nvidia-container-toolkit.enable = true;

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
