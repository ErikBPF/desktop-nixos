{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.apollo.module = {
    lib,
    modulesPath,
    pkgs,
    ...
  }: let
    safeAgentAliases = {
      claude = "command claude";
      c = "codex";
      cc = "code . ; codex";
      oc = "opencode";
      occ = "code . ; opencode";
    };
  in {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      m.nixos.nix-index
      m.nixos.hermes-client
      m.nixos.opencode-client
      m.nixos.apollo-syncthing
      m.nixos.kepler-nfs
      m.nixos.systemd-boot-counting
      m.nixos.apollo-hardware
      m.nixos.apollo-networking
      m.nixos.apollo-k3s-cluster
      m.nixos.first-boot
      m.nixos.runtime-secret-health
      m.nixos.pangolin-newt
      m.nixos.alloy
      m.nixos.power-desktop
      m.nixos.btrfs-snapshots
    ];

    services.btrfs.autoScrub.enable = true;
    environment.systemPackages = [pkgs.stern pkgs.nvd];
    modules.upgradeHealthCheck.extraCriticalUnits = ["microvms.target"];
    security.sudo.wheelNeedsPassword = lib.mkForce false;
    services.openssh.settings = {
      AllowTcpForwarding = lib.mkForce "local";
      GatewayPorts = "no";
    };

    # Current 64 GiB layout leaves about 20 GiB for the host while the five
    # cluster guests are running. Keep parallel builds bounded until 256 GiB.
    nix.settings = {
      max-jobs = lib.mkForce 6;
      cores = lib.mkForce 2;
    };

    users.users.${config.username} = {
      linger = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop"
      ];
    };

    home-manager.users.${config.username} = {
      imports = [
        m.home.atuin
        m.home.claude-code
        m.home.codex
        m.home.tuicr
        m.home.opencode
        m.home.vscode
        m.home.nvim
        m.home.hermes-agent
        m.home.herdr
        m.home.herdr-worklab
        m.home.grafatui
        m.home.tmux
      ];
      programs.bash.shellAliases = lib.mapAttrs (_: lib.mkForce) safeAgentAliases;
      programs.zsh.shellAliases = lib.mapAttrs (_: lib.mkForce) safeAgentAliases;
    };

    boot.loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 3;
    };

    system.autoUpgrade.enable = false;
    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
