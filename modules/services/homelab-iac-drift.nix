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

      discordWebhookFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to a file holding the Discord webhook URL for drift alerts (read at runtime; empty = log only).";
      };

      sopsAgeKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user}/.config/sops/age/keys.txt";
        defaultText = lib.literalExpression ''"/home/<user>/.config/sops/age/keys.txt"'';
        description = "Age key used to decrypt the repo's .env.sops.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.repoPath}/.terraform.d 0755 ${cfg.user} users - -"
        "d ${cfg.repoPath}/.terraform.d/plugin-cache 0755 ${cfg.user} users - -"
      ];

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
          SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
          # Without a shared plugin cache, `run --all` re-downloads every
          # provider (4 × tens of MB) for all 9 units on every scheduled run.
          TF_PLUGIN_CACHE_DIR = "${cfg.repoPath}/.terraform.d/plugin-cache";
        };

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          WorkingDirectory = cfg.repoPath;
          # Load the repo's secrets into the environment, then plan all units.
          # `sops exec-env` can't be used: it has no --input-type flag and
          # defaults to JSON-parsing the dotenv-format .env.sops (fails). So
          # decrypt with the explicit dotenv types (same as servarr-pull) and
          # export via `set -a`. Plaintext stays in a pipe — never on disk.
          ExecStart = pkgs.writeShellScript "homelab-iac-drift" ''
            cd ${lib.escapeShellArg cfg.repoPath}
            # Read the Discord webhook from its secret file (kept out of the Nix
            # store / process env baked at eval). drift-check.sh alerts if set.
            ${lib.optionalString (cfg.discordWebhookFile != "") ''
              [ -r ${lib.escapeShellArg cfg.discordWebhookFile} ] && export DISCORD_WEBHOOK_URL="$(cat ${lib.escapeShellArg cfg.discordWebhookFile})"
            ''}
            # Load each KEY=value via a quoted export (no shell-eval of values,
            # so spaces/metacharacters in PSKs/passphrases survive intact).
            # read -r with IFS='=' puts everything after the first '=' in v.
            while IFS='=' read -r k v; do
              case "$k" in ""|"#"*) continue ;; esac
              export "$k=$v"
            done < <(${pkgs.sops}/bin/sops --input-type dotenv --output-type dotenv --decrypt .env.sops)
            exec bash bin/drift-check.sh
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
