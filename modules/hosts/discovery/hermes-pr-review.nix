_: {
  flake.modules.nixos.discovery-hermes-pr-review = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hermes-pr-review;
    python = pkgs.python3;
    collect = pkgs.writeShellApplication {
      name = "hermes-pr-review-collect";
      runtimeInputs = [python pkgs.gh pkgs.git pkgs.curl pkgs.coreutils];
      text = ''
        exec ${python}/bin/python3 ${../../../scripts/pr-review/collect.py} "$@"
      '';
    };
    publish = pkgs.writeShellApplication {
      name = "hermes-pr-review-publish";
      runtimeInputs = [python pkgs.gh pkgs.coreutils];
      text = ''
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
  in {
    options.services.hermes-pr-review = {
      enable = lib.mkEnableOption "Collect, review, and publish Comet PR reviews with Hackerman";

      repo = lib.mkOption {
        type = lib.types.str;
        default = "apache/datafusion-comet";
      };
      author = lib.mkOption {
        type = lib.types.str;
        default = "ErikBPF";
      };
      botLogin = lib.mkOption {
        type = lib.types.str;
        default = "hermes-comet-reviewer";
        description = "Dedicated bot account login that owns the published comments.";
      };
      tokenFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/vault-agent/hermes-pr-review.env";
        description = "EnvironmentFile with GH_REVIEW_BOT_TOKEN. Read only by the host poster.";
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
      systemd.services.hermes-pr-review-bootstrap = {
        description = "Install the Hermes PR review cron job";
        after = ["vault-agent.service" "docker-${cfg.containerName}.service"];
        wants = ["vault-agent.service" "docker-${cfg.containerName}.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = "-${cfg.tokenFile}";
          ExecCondition = "${pkgs.bash}/bin/bash -c 'test -s ${cfg.tokenFile}'";
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
        description = "Collect Comet PR review bundles";
        after = ["vault-agent.service" "docker-${cfg.containerName}.service"];
        wants = ["vault-agent.service"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "hermes-pr-review";
          EnvironmentFile = "-${cfg.tokenFile}";
          ExecCondition = "${pkgs.bash}/bin/bash -c 'test -s ${cfg.tokenFile}'";
          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m 0755 ${cfg.dataDir}/review-in"
            "${pkgs.coreutils}/bin/install -d -o ${toString cfg.agentUid} -g ${toString cfg.agentGid} -m 0755 ${cfg.dataDir}/review-out"
          ];
          ExecStart = "${collect}/bin/hermes-pr-review-collect --repo ${cfg.repo} --author ${cfg.author} --data-dir ${cfg.dataDir} --state-dir /var/lib/hermes-pr-review";
          TimeoutStartSec = "10min";
        };
      };

      systemd.services.hermes-pr-review-publish = {
        description = "Publish Hermes PR reviews as bot comments";
        after = ["vault-agent.service"];
        wants = ["vault-agent.service"];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "hermes-pr-review";
          EnvironmentFile = "-${cfg.tokenFile}";
          ExecCondition = "${pkgs.bash}/bin/bash -c 'test -s ${cfg.tokenFile}'";
          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m 0755 ${cfg.dataDir}/review-in"
            "${pkgs.coreutils}/bin/install -d -o ${toString cfg.agentUid} -g ${toString cfg.agentGid} -m 0755 ${cfg.dataDir}/review-out"
          ];
          ExecStart = "${publish}/bin/hermes-pr-review-publish --data-dir ${cfg.dataDir} --state-dir /var/lib/hermes-pr-review --bot-login ${cfg.botLogin}";
          TimeoutStartSec = "5min";
        };
      };

      systemd.timers.hermes-pr-review-collect = {
        description = "Collect Comet PR review bundles periodically";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.collectInterval;
          Persistent = true;
          RandomizedDelaySec = "60s";
        };
      };

      systemd.timers.hermes-pr-review-publish = {
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
