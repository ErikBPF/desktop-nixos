{
  config,
  inputs,
  ...
}: let
  flakeConfig = config;
  m = flakeConfig.flake.modules;
in {
  configurations.nixos.endeavour.module = {
    config,
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
      m.nixos.harbor-reader
    ];

    home-manager.users.${flakeConfig.username} = {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.deepseek-harness
        m.home.monitor-layout-docked
      ];
      inherit (flakeConfig) colorScheme;
    };

    sops.secrets."openbao-harbor-reader-endeavour-role-id" = {
      sopsFile = ../../../secrets/sops/secrets.yaml;
      key = "openbao_harbor_reader_endeavour_role_id";
      owner = flakeConfig.username;
      mode = "0400";
    };
    sops.secrets."openbao-harbor-reader-endeavour-secret-id" = {
      sopsFile = ../../../secrets/sops/secrets.yaml;
      key = "openbao_harbor_reader_endeavour_secret_id";
      owner = flakeConfig.username;
      mode = "0400";
    };
    services.harborReader = {
      enable = true;
      address = "https://openbao.homelab.pastelariadev.com";
      roleIdFile = config.sops.secrets.openbao-harbor-reader-endeavour-role-id.path;
      secretIdFile = config.sops.secrets.openbao-harbor-reader-endeavour-secret-id.path;
      format = "docker";
      user = flakeConfig.username;
      authPath = "/run/user/1000/containers/auth.json";
    };

    environment.etc."libinput/local-overrides.quirks".text = ''
      [Positivo VAIO VJBK1BF11X Touchpad]
      MatchBus=i2c
      MatchVendor=0x093A
      MatchProduct=0x0255
      MatchUdevType=touchpad
      MatchDMIModalias=dmi:*:svnPositivoBahia-VAIO:pnVJBK1BF11X-*:*
      AttrEventCode=+BTN_RIGHT
    '';

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
    users.users.${flakeConfig.username}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzKv0yi/MC6TpRB3w2BAGYJw1gELHQSJuna9r8d0j8/"
    ];
  };
}
