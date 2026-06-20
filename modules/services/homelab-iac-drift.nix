# Scheduled Terraform/OpenTofu drift detection for the `homelab-iac` repo
# (UniFi + Tailscale + Cloudflare + AdGuard). Opt-in per host: the host must
# have the repo checked out and the sops age key for `.env.sops`. Providers
# need LAN/tailnet reach to the controllers, so enable this on a fleet host on
# the LAN (e.g. the laptop or discovery), not a cloud runner.
#
# Plans every Terragrunt unit (`bin/drift-check.sh`); alerts via ntfy on drift.
_: {
  flake.modules.nixos.homelab-iac-drift = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.homelabIacDrift;
  in {
    options.services.homelabIacDrift = {
      enable = lib.mkEnableOption "homelab-iac Terraform drift detection";

      repoPath = lib.mkOption {
        type = lib.types.str;
        example = "/home/erik/Documents/erik/homelab-iac";
        description = "Path to the homelab-iac checkout on this host.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        description = "User that owns the repo and the sops age key.";
      };

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 06:00:00";
        description = "systemd OnCalendar schedule for the drift check.";
      };

      ntfyUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Full ntfy topic URL for drift alerts (empty = log only).";
      };

      sopsAgeKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user}/.config/sops/age/keys.txt";
        defaultText = lib.literalExpression ''"/home/<user>/.config/sops/age/keys.txt"'';
        description = "Age key used to decrypt the repo's .env.sops.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.services.homelab-iac-drift = {
        description = "homelab-iac Terraform drift check";
        after = [
          "network-online.target"
          "tailscaled.service"
        ];
        wants = ["network-online.target"];

        path = with pkgs; [
          opentofu
          terragrunt
          sops
          age
          curl
          jq
          git
          gnugrep
          gnused
          coreutils
          bash
        ];

        environment = {
          TG_TF_PATH = "${pkgs.opentofu}/bin/tofu";
          NTFY_URL = cfg.ntfyUrl;
          SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
        };

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          WorkingDirectory = cfg.repoPath;
          # sops exec-env decrypts .env.sops and sets each var safely (no eval),
          # then runs the drift script which plans all units.
          ExecStart = pkgs.writeShellScript "homelab-iac-drift" ''
            cd ${lib.escapeShellArg cfg.repoPath}
            exec ${pkgs.sops}/bin/sops exec-env --input-type dotenv .env.sops 'bash bin/drift-check.sh'
          '';
        };
      };

      systemd.timers.homelab-iac-drift = {
        description = "homelab-iac drift check schedule";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.onCalendar;
          Persistent = true;
          RandomizedDelaySec = "15m";
        };
      };
    };
  };
}
