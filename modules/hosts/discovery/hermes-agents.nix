{
  config,
  inputs,
  self,
  ...
}: let
  inherit (config) username;
in {
  flake.modules.nixos.discovery-hermes-agents = {config, ...}: let
    litellmUrl = "http://litellm:4000/v1";
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
      image = "nousresearch/hermes-agent:latest";
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
      image = "nousresearch/hermes-agent:latest";
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
      settings =
        commonSettings
        // {
          skills.external_dirs = ["/opt/skills-meta" "/opt/skills-research"];
        };
    };
  };
}
