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
  }: let
    # Resolves the OpenBao-backed dev secrets into a 0600 env file at login.
    # The shell sources that file, so every agent session inherits GH_TOKEN
    # without depending on $XDG_CONFIG_HOME (opencode rewrites it for its
    # children, which is what hid the gh keyring login).
    resolveDevSecrets = pkgs.writeShellApplication {
      name = "resolve-dev-secrets";
      runtimeInputs = [pkgs.coreutils pkgs.secretspec];
      text = ''
        set -eu
        state="''${XDG_STATE_HOME:-$HOME/.local/state}/secretspec"
        out="$state/dev.env"
        install -d -m 0700 "$state"
        tmp="$(mktemp "$state/.dev.env.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        BAO_ROLE_ID="$(</run/secrets/openbao/github-token-reader-endeavour-role-id)" \
        BAO_SECRET_ID="$(</run/secrets/openbao/github-token-reader-endeavour-secret-id)" \
          secretspec export \
            --file "$HOME/.config/secretspec/desktop.toml" \
            --profile desktop \
            --format shell \
            --reason "endeavour login" > "$tmp"
        chmod 0600 "$tmp"
        mv -f "$tmp" "$out"
      '';
    };
  in {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-desktop
      m.nixos.desktop-workspaces
      m.nixos.endeavour-hardware
      m.nixos.endeavour-networking
      m.nixos.endeavour-always-on
      m.nixos.netbird-client
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

    home-manager.users.${flakeConfig.username} = {pkgs, ...}: {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.desktop-workspaces
        m.home.deepseek-harness
        m.home.monitor-layout-docked
      ];
      inherit (flakeConfig) colorScheme;

      # Dev credentials come from OpenBao through SecretSpec, over the
      # tailnet listener (plain HTTP inside WireGuard). The value lives only
      # at secret/iac/github; sops carries just the read-only AppRole.
      xdg.configFile."secretspec/desktop.toml".text = ''
        [project]
        name = "endeavour-desktop"
        revision = "1.0"

        [providers.bao_home]
        uri = "openbao://100.103.52.100:8200/secret?auth=approle&tls=false"

        [profiles.desktop]
        GH_TOKEN = { description = "GitHub CLI token maintained in OpenBao", ref = { item = "iac/github", field = "token" }, providers = ["bao_home"] }
      '';

      home.packages = [pkgs.secretspec];

      systemd.user.services.secretspec-export = {
        Unit.Description = "Resolve dev secrets from OpenBao into a 0600 env file";
        Service = {
          Type = "oneshot";
          ExecStart = "${resolveDevSecrets}/bin/resolve-dev-secrets";
          Restart = "on-failure";
          RestartSec = "30s";
        };
        Install.WantedBy = ["default.target"];
      };

      programs.zsh.initContent = ''
        # A stale cache keeps working when OpenBao is unreachable; the login
        # service replaces it. Break-glass: `gh auth login` (device flow).
        if [[ -r /run/secrets/openbao/github-token-reader-endeavour-role-id ]]; then
          export BAO_ROLE_ID="$(</run/secrets/openbao/github-token-reader-endeavour-role-id)"
        fi
        if [[ -r /run/secrets/openbao/github-token-reader-endeavour-secret-id ]]; then
          export BAO_SECRET_ID="$(</run/secrets/openbao/github-token-reader-endeavour-secret-id)"
        fi
        export SECRETSPEC_FILE="$HOME/.config/secretspec/desktop.toml"
        if [[ -r "''${XDG_STATE_HOME:-$HOME/.local/state}/secretspec/dev.env" ]]; then
          source "''${XDG_STATE_HOME:-$HOME/.local/state}/secretspec/dev.env"
        fi
      '';
    };

    # Only the read-only AppRole credentials are bootstrap material. The token
    # itself is written out of band and never enters this repo.
    sops.secrets."openbao-github-token-reader-endeavour-role-id" = {
      sopsFile = ../../../secrets/sops/secrets.yaml;
      key = "openbao_github_token_reader_endeavour_role_id";
      owner = flakeConfig.username;
      mode = "0400";
      path = "/run/secrets/openbao/github-token-reader-endeavour-role-id";
    };
    sops.secrets."openbao-github-token-reader-endeavour-secret-id" = {
      sopsFile = ../../../secrets/sops/secrets.yaml;
      key = "openbao_github_token_reader_endeavour_secret_id";
      owner = flakeConfig.username;
      mode = "0400";
      path = "/run/secrets/openbao/github-token-reader-endeavour-secret-id";
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
    nix.distributedBuildsApollo.enable = true;
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
    system.autoUpgrade.enable = false;
    services.openssh.enable = true;
    users.users.${flakeConfig.username}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzKv0yi/MC6TpRB3w2BAGYJw1gELHQSJuna9r8d0j8/"
    ];
  };
}
