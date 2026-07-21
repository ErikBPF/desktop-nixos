{
  config,
  inputs,
  self,
  ...
}: let
  inherit (config) username;
in {
  flake.modules.nixos.discovery-hermes-agents = {
    config,
    lib,
    ...
  }: let
    litellmUrl = "http://litellm:4000/v1";
    # Discord "Homelab" guild (1487679732215578774) ops channels watched by
    # Argus as N0 first-line responder. IDs are not secret.
    incidentsChannel = "1521191614846865568"; # #incidents
    deploysChannel = "1521191597566332938"; # #deploys
    commonSettings = {
      model = {
        provider = "custom";
        default = "glm-5";
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

    sops.secrets."hermes_agents/daedalus_env" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "hermes_agents/daedalus_env";
      mode = "0400";
      path = "/run/secrets/hermes-daedalus";
      restartUnits = ["docker-hermes-daedalus.service"];
    };
    sops.secrets."hermes_agents/argus_env" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "hermes_agents/argus_env";
      mode = "0400";
      path = "/run/secrets/hermes-argus";
      restartUnits = ["docker-hermes-argus.service"];
    };

    services.hermes-agent-oci-daedalus = {
      enable = true;
      enableHealthcheck = false;
      image = "nousresearch/hermes-agent@sha256:229429fe176efa05ca4e542a7e11348482b40c36f903191498c7016f1dfc1019";
      hostDataDir = "/home/${username}/homelab/apps/hermes-daedalus";
      environmentFile = config.sops.secrets."hermes_agents/daedalus_env".path;
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
      enableHealthcheck = false;
      image = "nousresearch/hermes-agent@sha256:229429fe176efa05ca4e542a7e11348482b40c36f903191498c7016f1dfc1019";
      hostDataDir = "/home/${username}/homelab/apps/hermes-argus";
      environmentFile = config.sops.secrets."hermes_agents/argus_env".path;
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
        # Scrutiny, cron posters) and Argus goes blind to the very alerts it
        # watches — channel-scoped auth only applies when no user/role
        # allowlist exists (upstream adapter._is_user_allowed). DMs are
        # therefore denied; talk to Argus inside the two channels.
        DISCORD_ALLOWED_CHANNELS = "${incidentsChannel},${deploysChannel}";
      };
      settings = lib.recursiveUpdate commonSettings {
        skills.external_dirs = ["/opt/skills-meta" "/opt/skills-research"];
        # Respond without @-mention in the two ops channels. Leave the
        # upstream default bots_require_inline_mention=false so bot/webhook
        # posts (Grafana alerts) wake the agent; Argus itself never posts as
        # a trigger for other bots, so no ping-pong loop exists here.
        discord.free_response_channels = "${incidentsChannel},${deploysChannel}";
        # Structured Grafana ingest (staged). deliver_only=true stores the
        # signed payload without triggering the agent — Discord listening is
        # the trigger for now, so alerts don't double-fire. Flip to false when
        # the webhook becomes the primary trigger and Discord the human
        # mirror. Requires WEBHOOK_GRAFANA_ALERTS_SECRET in argus_env AND the
        # same value in OpenBao secret/shared/discord.argus_webhook_hmac
        # (Grafana signs body-only HMAC-SHA256, hex, into X-Webhook-Signature
        # — the upstream generic V1 scheme; Grafana's timestamped mode signs
        # "ts:body" which hermes V2 ("ts.body") rejects, so keep body-only).
        platforms.webhook.extra.routes.grafana-alerts = {
          hmac_secret_env = "WEBHOOK_GRAFANA_ALERTS_SECRET";
          deliver_only = true;
          prompt = ''
            Grafana alert webhook ({{ payload.status }}) via {{ payload.receiver }}:
            {% for a in payload.alerts %}
            - [{{ a.status }}] {{ a.labels.alertname }} host={{ a.labels.instance }} — {{ a.annotations.summary }}
            {% endfor %}
          '';
        };
      };
    };
  };
}
