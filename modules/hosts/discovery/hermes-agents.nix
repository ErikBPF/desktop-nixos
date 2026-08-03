{
  config,
  inputs,
  ...
}: let
  inherit (config) username;
in {
  flake.modules.nixos.discovery-hermes-agents = {
    config,
    lib,
    pkgs,
    ...
  }: let
    litellmUrl = "http://litellm:4000/v1";
    # Discord "Homelab" guild (1487679732215578774) ops channels watched by
    # Cleytin (stable runtime ID: argus) as N0 first-line responder. IDs are
    # not secret.
    incidentsChannel = "1521191614846865568"; # #incidents
    deploysChannel = "1521191597566332938"; # #deploys
    securityChannel = "1530261608419299428"; # #security
    commonSettings = {
      model = {
        provider = "custom";
        default = "deepseek-v4-flash";
        base_url = litellmUrl;
        api_key = "\${OPENAI_API_KEY}";
      };
      auxiliary = {
        compression = {
          provider = "custom";
          model = "mimo";
          base_url = litellmUrl;
          api_key = "\${OPENAI_API_KEY}";
        };
        session_search = {
          provider = "custom";
          model = "mimo";
          base_url = litellmUrl;
          api_key = "\${OPENAI_API_KEY}";
        };
      };
      memory = {
        memory_char_limit = 10000;
        user_char_limit = 3000;
      };
      approvals.mode = "off";
      platforms.telegram.enabled = false;
      model_aliases = {
        deepseek = {
          model = "deepseek-v4-flash";
          provider = "custom";
          base_url = litellmUrl;
        };
        glm = {
          model = "glm-5";
          provider = "custom";
          base_url = litellmUrl;
        };
        kimi = {
          model = "kimi-k2-code";
          provider = "custom";
          base_url = litellmUrl;
        };
        mimo = {
          model = "mimo";
          provider = "custom";
          base_url = litellmUrl;
        };
        mimo-pro = {
          model = "mimo-pro";
          provider = "custom";
          base_url = litellmUrl;
        };
      };
    };
  in {
    imports = [
      inputs.hermes-flake.nixosModules.hermes-agent-oci-daedalus
      inputs.hermes-flake.nixosModules.hermes-agent-oci-argus
    ];

    assertions = [
      {
        assertion = builtins.match "^nousresearch/hermes-agent@sha256:[0-9a-f]{64}$" config.services.hermes-agent-oci-daedalus.image != null;
        message = "Discovery Daedalus Hermes image must use an immutable sha256 digest";
      }
      {
        assertion = builtins.match "^nousresearch/hermes-agent@sha256:[0-9a-f]{64}$" config.services.hermes-agent-oci-argus.image != null;
        message = "Discovery Argus Hermes image must use an immutable sha256 digest";
      }
    ];

    services.hermes-agent-oci-daedalus = {
      enable = true;
      enableHealthcheck = false;
      image = "nousresearch/hermes-agent@sha256:229429fe176efa05ca4e542a7e11348482b40c36f903191498c7016f1dfc1019";
      hostDataDir = "/home/${username}/homelab/apps/hermes-daedalus";
      environmentFile = "/run/vault-agent/hermes-daedalus.env";
      openBindAddress = "0.0.0.0";
      publishPorts = false;
      openaiBaseUrl = litellmUrl;
      memoryMax = "2g";
      networks = ["homelab-net"];
      soulFile = ./daedalus-SOUL.md;
      extraVolumes = [
        "/home/${username}/hermes-skills/meta:/opt/skills-meta:ro"
        "/home/${username}/hermes-skills/research:/opt/skills-research:ro"
        "/home/${username}/hermes-skills/development:/opt/skills-development:ro"
        "/var/lib/hermes-wiki:/opt/wiki:ro"
      ];
      settings =
        commonSettings
        // {
          skills.external_dirs = ["/opt/skills-meta" "/opt/skills-research" "/opt/skills-development"];
          mcp_servers = {
            docs_search = {
              url = "http://kepler:8765/mcp";
              headers.Authorization = "Bearer \${DOCS_SEARCH_API_KEY}";
              connect_timeout = 30;
              timeout = 120;
              supports_parallel_tool_calls = true;
              tools = {
                include = ["search_docs" "fetch_chunk" "source_status"];
                resources = false;
                prompts = false;
              };
              sampling.enabled = false;
            };
            context7 = {
              url = "https://mcp.context7.com/mcp";
              connect_timeout = 30;
              timeout = 120;
              tools = {
                include = ["resolve-library-id" "query-docs"];
                resources = false;
                prompts = false;
              };
              sampling.enabled = false;
            };
          };
        };
    };

    services.hermes-agent-oci-argus = {
      enable = true;
      enableHealthcheck = true;
      image = "nousresearch/hermes-agent@sha256:229429fe176efa05ca4e542a7e11348482b40c36f903191498c7016f1dfc1019";
      hostDataDir = "/home/${username}/homelab/apps/hermes-argus";
      environmentFile = "/run/vault-agent/hermes-argus.env";
      openBindAddress = "0.0.0.0";
      publishPorts = false;
      openaiBaseUrl = litellmUrl;
      memoryMax = "2g";
      networks = ["homelab-net"];
      soulFile = ./argus-SOUL.md;
      extraVolumes = [
        "/home/${username}/hermes-skills/meta:/opt/skills-meta:ro"
        "/home/${username}/hermes-skills/research:/opt/skills-research:ro"
        "/var/lib/hermes-wiki:/opt/wiki:ro"
        "${./homelab-SOUL.md}:/opt/context/homelab-SOUL.md:ro"
      ];
      extraEnvironment = {
        # N0 channel scoping. Deliberately NO DISCORD_ALLOWED_USERS: with a
        # user allowlist set, the adapter denies webhook/bot authors (Grafana,
        # Scrutiny, cron posters) and Cleytin goes blind to the very alerts it
        # watches — channel-scoped auth only applies when no user/role
        # allowlist exists (upstream adapter._is_user_allowed). DMs are
        # therefore denied; talk to Cleytin inside the alert channels.
        DISCORD_ALLOWED_CHANNELS = "${incidentsChannel},${deploysChannel},${securityChannel}";
        DISCORD_HOME_CHANNEL = incidentsChannel;
        # Alert publishers mention Cleytin explicitly. Accept only mentioned
        # bot/webhook posts so unrelated automation cannot trigger the agent.
        DISCORD_ALLOW_BOTS = "mentions";
      };
      settings = lib.recursiveUpdate commonSettings {
        # Channel messages and alert payloads are untrusted input. Hermes has
        # no command allowlist, so prompt-only "read-only" rules are not a
        # security boundary.
        agent.disabled_toolsets = ["terminal" "kanban"];
        platform_toolsets = {
          discord = [];
          webhook = [];
        };
        skills.external_dirs = ["/opt/skills-meta" "/opt/skills-research"];
        # Structured Grafana ingest. Hermes authenticates every route with its
        # native WEBHOOK_SECRET rendered by Vault Agent at runtime.
        platforms.webhook.extra.routes.grafana-alerts = {
          deliver = "discord";
          deliver_extra.chat_id = incidentsChannel;
          filters = [
            {
              field = "payload.status";
              equals = "firing";
            }
          ];
          prompt = ''
            Grafana alert webhook ({status}) via {receiver}:
            {__raw__}
          '';
        };
      };
    };

    systemd.services.docker-hermes-daedalus = {
      after = ["vault-agent.service"];
      requires = ["vault-agent.service"];
      serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-hermes-daedalus-env" ''
        for _ in $(seq 1 100); do
          [ -s /run/vault-agent/hermes-daedalus.env ] && exit 0
          sleep 0.1
        done
        exit 1
      '';
    };

    systemd.services.docker-hermes-argus = {
      after = ["vault-agent.service"];
      requires = ["vault-agent.service"];
      serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-hermes-argus-env" ''
        for _ in $(seq 1 100); do
          [ -s /run/vault-agent/hermes-argus.env ] && exit 0
          sleep 0.1
        done
        exit 1
      '';
    };

    systemd.services.hermes-argus-healthcheck.serviceConfig.ExecStart = lib.mkForce (pkgs.writeShellScript "hermes-argus-healthcheck" ''
      for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
        if output="$(${pkgs.docker}/bin/docker exec hermes-argus /opt/hermes/.venv/bin/python -c 'import json,time,yaml; from hermes_cli.tools_config import _get_platform_tools; cfg=yaml.safe_load(open("/opt/data/config.yaml")); assert "terminal" in cfg["agent"]["disabled_toolsets"]; assert "kanban" in cfg["agent"]["disabled_toolsets"]; assert not _get_platform_tools(cfg,"discord"); assert not _get_platform_tools(cfg,"webhook"); state=json.load(open("/opt/data/gateway_state.json")); assert state["gateway_state"] == "running"; assert state["platforms"]["discord"]["state"] == "connected"; heartbeat=json.load(open("/opt/data/state/gateway.heartbeat")); age=time.monotonic() - heartbeat["monotonic"]; assert 0 <= age < 120' 2>&1)"; then
          exit 0
        fi
        if [ "$attempt" -eq 30 ]; then
          printf '%s\n' "$output" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
    '');
  };
}
