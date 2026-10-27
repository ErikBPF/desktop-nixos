# Scheduled Terraform/OpenTofu drift detection for the `homelab-iac` repo
# (UniFi + Tailscale + Cloudflare + AdGuard). Opt-in per host: the host must
# has the sops age key for the pinned artifact's `.env.sops`. Providers need
# LAN/tailnet reach to the controllers, so enable this on a fleet host on the
# LAN (e.g. the laptop or discovery), not a cloud runner.
#
# Plans every Terragrunt unit (`bin/drift-check.sh`); alerts via ntfy on drift.
{inputs, ...}: {
  flake.modules.nixos.homelab-iac-drift = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.homelabIacDrift;

    unitPath = with pkgs; [
      opentofu
      terragrunt
      sops
      age
      curl
      jq
      git
      openssh
      docker
      openbao
      util-linux
      gnugrep
      gnused
      gawk
      coreutils
      bash
    ];

    # Provider credentials shared by the scheduled check and the merged-main
    # apply. The caller must already be cd'd into the revision to evaluate.
    providerEnv = ''
      # Read the Discord webhook from its secret file (kept out of the Nix
      # store / process env baked at eval). The scripts alert if it is set.
      ${lib.optionalString (cfg.discordWebhookFile != "") ''
        [ -r ${lib.escapeShellArg cfg.discordWebhookFile} ] && export DISCORD_WEBHOOK_URL="$(cat ${lib.escapeShellArg cfg.discordWebhookFile})"
      ''}
      ${lib.optionalString (cfg.litellmContainer != "") ''
        litellm_api_base=${lib.escapeShellArg cfg.litellmApiBase}
        if [ -z "$litellm_api_base" ]; then
          litellm_ip="$(${pkgs.docker}/bin/docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${lib.escapeShellArg cfg.litellmContainer})"
          [ -n "$litellm_ip" ] || {
            echo "homelab-iac: unable to discover LiteLLM container IP" >&2
            exit 1
          }
          litellm_api_base="http://$litellm_ip:4000"
        fi
        export LITELLM_API_BASE="$litellm_api_base"
        export LITELLM_API_KEY="$(${pkgs.docker}/bin/docker exec ${lib.escapeShellArg cfg.litellmContainer} printenv LITELLM_MASTER_KEY)"
      ''}
      # Load each KEY=value via a quoted export (no shell-eval of values,
      # so spaces/metacharacters in PSKs/passphrases survive intact).
      # IFS= (empty) + parameter expansion: split on the FIRST '=' only.
      # `IFS='=' read` would strip a single trailing '=' from the value —
      # i.e. base64 padding — corrupting keys like OCI_private_key_b64
      # (base64decode then fails and the oracle units error out).
      while IFS= read -r line; do
        case "$line" in ""|"#"*) continue ;; esac
        key="''${line%%=*}"
        value="''${line#*=}"
        value="''${value%\"}"
        value="''${value#\"}"
        value="''${value%\'}"
        value="''${value#\'}"
        export "$key=$value"
      done < <(
        ${pkgs.sops}/bin/sops --input-type dotenv --output-type dotenv --decrypt .env.sops
        cat ${lib.escapeShellArg cfg.githubAppManagementEnvFile}
      )
      # GitHub provider token: homelab-iac retired the .env.sops copy
      # (#139) and keeps the only copy in OpenBao secret/iac/github.
      # Resolve it with the reader AppRole that .env.sops already holds.
      bao_token="$(BAO_ADDR=http://127.0.0.1:8200 ${pkgs.openbao}/bin/bao write -field=token \
        auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")"
      export GITHUB_TOKEN="$(BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$bao_token" \
        ${pkgs.openbao}/bin/bao kv get -field=token -mount=secret iac/github)"
      unset bao_token
      export BAO_ADDR=http://127.0.0.1:8200
      export BAO_TOKEN="$(cat /run/vault-agent/token)"
      export GITHUB_APP_MANAGEMENT_REFRESH_TOKEN="$(${pkgs.openbao}/bin/bao kv get -field=GITHUB_APP_MANAGEMENT_REFRESH_TOKEN -mount=secret home/github-app-management)"
      export GITHUB_APP_MANAGEMENT_TOKEN="$(bash bin/refresh-github-app-token.sh)"
    '';
  in {
    options.services.homelabIacDrift = {
      enable = lib.mkEnableOption "homelab-iac Terraform drift detection";

      user = lib.mkOption {
        type = lib.types.str;
        description = "User that owns the repo and the sops age key.";
      };

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 06:00:00";
        description = "systemd OnCalendar schedule for the drift check.";
      };

      applyMergedMain = lib.mkEnableOption "applying the merged homelab-iac main revision after each merge";

      mainPollInterval = lib.mkOption {
        type = lib.types.str;
        default = "5min";
        description = "How often to poll GitHub for a new homelab-iac main revision.";
      };

      applyDenylist = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["tailscale/acl"];
        description = "Units whose drift is alerted but never applied automatically (a wholesale ACL overwrite can cut admin access).";
      };

      discordWebhookFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to a file holding the Discord webhook URL for drift alerts (read at runtime; empty = log only).";
      };

      githubAppManagementEnvFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/vault-agent/github-app-management.env";
        description = "Vault-rendered OAuth client and refresh token used to obtain an ephemeral GitHub App management token.";
      };

      sopsAgeKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user}/.config/sops/age/keys.txt";
        defaultText = lib.literalExpression ''"/home/<user>/.config/sops/age/keys.txt"'';
        description = "Age key used to decrypt the repo's .env.sops.";
      };

      ociSshPubKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Path to the SSH public key the oracle/compute* units inject
          (OCI_SSH_PUBKEY_FILE). The units `cat` it at plan time; on a headless
          host it must exist and match the key in state, else `run --all` errors
          out and the whole drift check fails. Empty = leave unset (defaults to
          ~/.ssh/id_ed25519.pub).
        '';
      };

      ociConsoleSshPubKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to the RSA SSH public key used by OCI serial console connections.";
      };

      litellmContainer = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Local container whose LITELLM_MASTER_KEY authenticates LiteLLM provider plans.";
      };

      litellmApiBase = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional LiteLLM provider API endpoint; empty discovers the container IP.";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.services.homelab-iac-drift = {
        description = "homelab-iac Terraform drift check";
        after = [
          "network-online.target"
          "tailscaled.service"
          "vault-agent.service"
        ];
        wants = ["network-online.target"];

        path = unitPath;

        environment =
          {
            TG_TF_PATH = "${pkgs.opentofu}/bin/tofu";
            SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
            # Without a shared plugin cache, `run --all` re-downloads every
            # provider for all units on every run. The cache directory is a
            # systemd CacheDirectory in ExecStart, shared with the apply unit.
          }
          // lib.optionalAttrs (cfg.ociSshPubKeyFile != "") {
            OCI_SSH_PUBKEY_FILE = cfg.ociSshPubKeyFile;
          }
          // lib.optionalAttrs (cfg.ociConsoleSshPubKeyFile != "") {
            OCI_CONSOLE_PUBKEY_FILE = cfg.ociConsoleSshPubKeyFile;
          };

        serviceConfig = {
          Type = "oneshot";
          SuccessExitStatus = [2];
          User = cfg.user;
          StateDirectory = "homelab-iac-drift";
          StateDirectoryMode = "0700";
          CacheDirectory = "homelab-iac-tf-plugin-cache";
          WorkingDirectory = "/var/lib/homelab-iac-drift";
          # Load the repo's secrets into the environment, then plan all units.
          # `sops exec-env` can't be used: it has no --input-type flag and
          # defaults to JSON-parsing the dotenv-format .env.sops (fails). So
          # decrypt with the explicit dotenv types (same as servarr-pull) and
          # export via `set -a`. Plaintext stays in a pipe — never on disk.
          ExecStart = pkgs.writeShellScript "homelab-iac-drift" ''
            set -euo pipefail
            rm -rf "$STATE_DIRECTORY/source"
            cp -R --no-preserve=mode ${inputs.homelab-iac} "$STATE_DIRECTORY/source"
            git -c init.defaultBranch=main init --quiet "$STATE_DIRECTORY/source"
            export TF_PLUGIN_CACHE_DIR="$CACHE_DIRECTORY"
            mkdir -p "$TF_PLUGIN_CACHE_DIR"
            cd "$STATE_DIRECTORY/source"
            ${providerEnv}
            # Serialize with the apply poller instead of killing it: both take
            # this lock, so an apply waits for an in-flight plan.
            exec flock -w 900 "$CACHE_DIRECTORY/run.lock" bash bin/drift-check.sh
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

      # Merge-to-main apply. Polls the public repo (no inbound port, no GitHub
      # runner on the LAN) and evaluates the merged revision, not the pinned
      # flake input, so a merge is planned and applied as written.
      systemd.services.homelab-iac-main-apply = lib.mkIf cfg.applyMergedMain {
        description = "Apply the merged homelab-iac main revision";
        after = [
          "network-online.target"
          "tailscaled.service"
          "vault-agent.service"
        ];
        wants = ["network-online.target"];

        path = unitPath;

        environment =
          {
            TG_TF_PATH = "${pkgs.opentofu}/bin/tofu";
            SOPS_AGE_KEY_FILE = cfg.sopsAgeKeyFile;
            IAC_APPLY_DENYLIST = lib.concatStringsSep " " cfg.applyDenylist;
          }
          // lib.optionalAttrs (cfg.ociSshPubKeyFile != "") {
            OCI_SSH_PUBKEY_FILE = cfg.ociSshPubKeyFile;
          }
          // lib.optionalAttrs (cfg.ociConsoleSshPubKeyFile != "") {
            OCI_CONSOLE_PUBKEY_FILE = cfg.ociConsoleSshPubKeyFile;
          };

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          StateDirectory = "homelab-iac-main-apply";
          StateDirectoryMode = "0700";
          CacheDirectory = "homelab-iac-tf-plugin-cache";
          WorkingDirectory = "/var/lib/homelab-iac-main-apply";
          ExecStart = pkgs.writeShellScript "homelab-iac-main-apply" ''
            set -euo pipefail
            repo="$STATE_DIRECTORY/source"
            if [ -d "$repo/.git" ]; then
              git -C "$repo" fetch --quiet --depth 1 origin main
              git -C "$repo" reset --quiet --hard FETCH_HEAD
            else
              git clone --quiet --depth 1 https://github.com/ErikBPF/homelab-iac "$repo"
            fi
            cd "$repo"
            sha="$(git rev-parse HEAD)"
            # One evaluation per merged revision. A refusal or failure is
            # recorded too, so a bad revision does not re-alert every poll;
            # delete $STATE_DIRECTORY/{refused,failed}-sha to retry by hand.
            for marker in applied-sha refused-sha failed-sha; do
              if [ "$sha" = "$(cat "$STATE_DIRECTORY/$marker" 2>/dev/null || true)" ]; then
                echo "homelab-iac apply: $sha already handled ($marker)"
                exit 0
              fi
            done
            export TF_PLUGIN_CACHE_DIR="$CACHE_DIRECTORY"
            mkdir -p "$TF_PLUGIN_CACHE_DIR"
            ${providerEnv}
            rc=0
            # Same lock as the daily plan: wait for it instead of killing it.
            # -E 75 keeps "lock busy" distinct from a real apply failure (1);
            # a wait is not a verdict on the revision, so retry next poll.
            flock -w 900 -E 75 "$CACHE_DIRECTORY/run.lock" bash bin/iac-apply.sh || rc=$?
            case "$rc" in
              0) printf '%s' "$sha" > "$STATE_DIRECTORY/applied-sha" ;;
              75) echo "homelab-iac apply: plan lock busy, retrying next poll" ;;
              3) printf '%s' "$sha" > "$STATE_DIRECTORY/refused-sha" ;;
              *)
                printf '%s' "$sha" > "$STATE_DIRECTORY/failed-sha"
                exit "$rc"
                ;;
            esac
          '';
        };
      };

      systemd.timers.homelab-iac-main-apply = lib.mkIf cfg.applyMergedMain {
        description = "Merged homelab-iac main poll";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = cfg.mainPollInterval;
          RandomizedDelaySec = "1min";
          Persistent = true;
          Unit = "homelab-iac-main-apply.service";
        };
      };
    };
  };
}
