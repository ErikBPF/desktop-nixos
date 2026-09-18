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
      m.nixos.first-boot
      m.nixos.runtime-secret-health
      m.nixos.pangolin-newt
      m.nixos.alloy
      m.nixos.power-desktop
      m.nixos.btrfs-snapshots
    ];

    services.btrfs.autoScrub.enable = true;
    environment.systemPackages = [pkgs.stern pkgs.nvd];
    # Operator-owned trial storage; never create it on root if the mirror is absent.
    # Future inference units must require the same mount before accessing it.
    systemd.services.apollo-ai-storage = {
      description = "Prepare private AI model and cache directories on the mirror";
      wantedBy = ["multi-user.target"];
      unitConfig = {
        RequiresMountsFor = "/mnt/data";
        AssertPathIsMountPoint = "/mnt/data";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/install -d -m 0700 -o ${config.username} -g users /mnt/data/ai /mnt/data/ai/models /mnt/data/ai/cache";
      };
    };
    security.sudo.wheelNeedsPassword = lib.mkForce false;
    services.openssh.settings = {
      AllowTcpForwarding = lib.mkForce "local";
      GatewayPorts = "no";
    };

    # Operator baseline: bound build concurrency so interactive work stays
    # responsive on this 28-thread host.
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
      systemd-boot.configurationLimit = 6;
    };

    system.autoUpgrade.enable = false;
    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
