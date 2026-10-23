_: {
  flake.modules.nixos.discovery-hermes-pr-review = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hermes-pr-review;
    python = pkgs.python3;
    tokenGate = pkgs.writeShellScript "hermes-pr-review-token-gate" ''
      set -eu
      if [ -s ${cfg.appCredentialFile} ] && ${pkgs.jq}/bin/jq -e \
        '.app_id and (.installation_id|tostring|length>0) and (.private_key|length>0)' \
        ${cfg.appCredentialFile} >/dev/null 2>&1; then
        exit 0
      fi
      if [ -s ${cfg.upstreamTokenFile} ] && \
        ${pkgs.gnugrep}/bin/grep -q '^GH_REVIEW_UPSTREAM_TOKEN=..*' ${cfg.upstreamTokenFile}; then
        exit 0
      fi
      exit 1
    '';
    collect = pkgs.writeShellApplication {
      name = "hermes-pr-review-collect";
      runtimeInputs = [python pkgs.gh pkgs.git pkgs.curl pkgs.openssl pkgs.coreutils];
      text = ''
        export PYTHONPATH=${../../../scripts/pr-review}
        exec ${python}/bin/python3 ${../../../scripts/pr-review/collect.py} "$@"
      '';
    };
    publish = pkgs.writeShellApplication {
      name = "hermes-pr-review-publish";
      runtimeInputs = [python pkgs.gh pkgs.openssl pkgs.coreutils];
      text = ''
        export PYTHONPATH=${../../../scripts/pr-review}
        exec ${python}/bin/python3 ${../../../scripts/pr-review/publish.py} "$@"
      '';
    };
    bootstrap = pkgs.writeShellApplication {
      name = "hermes-pr-review-bootstrap";
      runtimeInputs = [pkgs.docker pkgs.coreutils pkgs.gnugrep pkgs.bash];
      text = ''
        export DATA_DIR=${lib.escapeShellArg cfg.dataDir}
        export READY_SCRIPT=${lib.escapeShellArg "${../../../scripts/pr-review/ready.py}"}
        export HERMES_CONTAINER=${lib.escapeShellArg cfg.containerName}
        export HERMES_CLI=${lib.escapeShellArg cfg.hermesCli}
        export AGENT_UID=${toString cfg.agentUid}
        export AGENT_GID=${toString cfg.agentGid}
        export JOB_NAME=${lib.escapeShellArg cfg.jobName}
        export SCHEDULE=${lib.escapeShellArg cfg.schedule}
        exec ${pkgs.bash}/bin/bash ${../../../scripts/pr-review/bootstrap-cron.sh}
      '';
    };
    configFile = pkgs.writeText "hermes-pr-review-repos.json" (builtins.toJSON {
      repos =
        map (entry: {
          repo = entry.repo;
          author = entry.author;
          credential = entry.credential;
          bot_login = entry.botLogin;
        })
        cfg.repos;
    });
  in {
    options.services.hermes-pr-review = {
      enable = lib.mkEnableOption "Collect, review, and publish PR reviews with Hackerman";

      repos = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            repo = lib.mkOption {
              type = lib.types.str;
              description = "owner/name";
            };
            author = lib.mkOption {
              type = lib.types.str;
              default = "ErikBPF";
            };
            credential = lib.mkOption {
              type = lib.types.enum ["app" "upstream"];
              default = "app";
              description = "app for repos where the GitHub App is installed; upstream for public repos outside the account's admin.";
            };
            botLogin = lib.mkOption {
              type = lib.types.str;
              default = "hackerman-cr[bot]";
              description = "Login that owns the bot comment. App installations use '<slug>[bot]'.";
            };
          };
        });
        default = [];
      };

      appCredentialFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/vault-agent/hermes-pr-review-app.json";
        description = "JSON with app_id, installation_id, and private_key.";
      };
      upstreamTokenFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/vault-agent/hermes-pr-review-upstream.env";
        description = "EnvironmentFile with GH_REVIEW_UPSTREAM_TOKEN.";
      };
      appTokenCache = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/hermes-pr-review/app-token.json";
      };
      allowPublish = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Post bot comments. Keep false until a human has approved a dry-run packet.";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = config.services.hermes-agent-oci-daedalus.hostDataDir;
      };
      containerName = lib.mkOption {
        type = lib.types.str;
        default = "hermes-daedalus";
      };
      hermesCli = lib.mkOption {
        type = lib.types.str;
        default = "/opt/hermes/.venv/bin/hermes";
      };
      agentUid = lib.mkOption {
        type = lib.types.int;
        default = 10000;
      };
      agentGid = lib.mkOption {
        type = lib.types.int;
        default = 10000;
      };
      jobName = lib.mkOption {
        type = lib.types.str;
        default = "hermes-pr-review";
      };
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "*/10 * * * *";
      };
      collectInterval = lib.mkOption {
        type = lib.types.str;
        default = "10min";
      };
      publishInterval = lib.mkOption {
        type = lib.types.str;
        default = "5min";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.repos != [];
          message = "services.hermes-pr-review.repos must not be empty";
        }
      ];

      systemd.services.hermes-pr-review-bootstrap = {
        description = "Install the Hermes PR review cron job";
        after = ["vault-agent.service" "docker-${cfg.containerName}.service"];
        wants = ["vault-agent.service" "docker-${cfg.containerName}.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecCondition = "${tokenGate}";
          ExecStart = "${bootstrap}/bin/hermes-pr-review-bootstrap";
        };
      };

      systemd.timers.hermes-pr-review-bootstrap = {
        description = "Retry the Hermes PR review cron bootstrap until it succeeds";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "10min";
          Persistent = true;
          RandomizedDelaySec = "30s";
        };
      };

      systemd.services.hermes-pr-review-collect = {
        description = "Collect PR review bundles";
        after = ["vault-agent.service" "docker-${cfg.containerName}.service"];
        wants = ["vault-agent.service"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "hermes-pr-review";
          EnvironmentFile = "-${cfg.upstreamTokenFile}";
          ExecCondition = "${tokenGate}";
          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m 0755 ${cfg.dataDir}/review-in"
            "${pkgs.coreutils}/bin/install -d -o ${toString cfg.agentUid} -g ${toString cfg.agentGid} -m 0755 ${cfg.dataDir}/review-out"
          ];
          ExecStart = "${collect}/bin/hermes-pr-review-collect --config ${configFile} --data-dir ${cfg.dataDir} --state-dir /var/lib/hermes-pr-review --app-credential ${cfg.appCredentialFile} --app-token-cache ${cfg.appTokenCache}";
          TimeoutStartSec = "15min";
        };
      };

      systemd.services.hermes-pr-review-publish = lib.mkIf cfg.allowPublish {
        description = "Publish Hermes PR reviews as bot comments";
        after = ["vault-agent.service"];
        wants = ["vault-agent.service"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "hermes-pr-review";
          EnvironmentFile = "-${cfg.upstreamTokenFile}";
          ExecCondition = "${tokenGate}";
          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m 0755 ${cfg.dataDir}/review-in"
            "${pkgs.coreutils}/bin/install -d -o ${toString cfg.agentUid} -g ${toString cfg.agentGid} -m 0755 ${cfg.dataDir}/review-out"
          ];
          ExecStart = "${publish}/bin/hermes-pr-review-publish --config ${configFile} --data-dir ${cfg.dataDir} --state-dir /var/lib/hermes-pr-review --app-credential ${cfg.appCredentialFile} --app-token-cache ${cfg.appTokenCache}";
          TimeoutStartSec = "5min";
        };
      };

      systemd.timers.hermes-pr-review-collect = {
        description = "Collect PR review bundles periodically";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.collectInterval;
          Persistent = true;
          RandomizedDelaySec = "60s";
        };
      };

      systemd.timers.hermes-pr-review-publish = lib.mkIf cfg.allowPublish {
        description = "Publish Hermes PR reviews periodically";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "8min";
          OnUnitActiveSec = cfg.publishInterval;
          Persistent = true;
          RandomizedDelaySec = "30s";
        };
      };
    };
  };
}
