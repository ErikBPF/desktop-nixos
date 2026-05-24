{
  config,
  inputs,
  self,
  ...
}: {
  flake.modules.nixos.discovery-hermes-agent = {
    config,
    lib,
    pkgs,
    ...
  }: let
    litellmUrl = "https://litellm.homelab.pastelariadev.com/v1";
  in {
    imports = [
      # Pick ONE of the two below:
      inputs.hermes-flake.nixosModules.hermes-agent-container
      # inputs.hermes-flake.nixosModules.default  # bare-metal alternative
    ];

    # Sops secret carrying the hermes env dotenv. Define via
    # `sops secrets/sops/secrets.yaml` under a `hermes_server.env: |` block.
    sops.secrets."hermes_server/env" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      format = "yaml";
      key = "hermes_server/env";
      mode = "0440";
      owner = "hermes";
      group = "hermes";
      path = "/run/secrets/hermes-agent";
      restartUnits = ["container@hermes.service"];
    };

    # CONTAINER MODE (recommended — declarative nspawn isolation):
    services.hermes-agent-container = {
      enable = true;
      containerName = "hermes";
      privateNetwork = false;
      hostDataDir = "/var/lib/hermes-agent";
      hostSecretsPath = config.sops.secrets."hermes_server/env".path;
      apiPort = 8642;
      webhookPort = 8644;
      telegramAllowedUsers = [7729797827];
      openaiBaseUrl = litellmUrl;

      # Homelab-specific settings overlaid on the flake's vendor-neutral defaults.
      settings = {
        # Override neutral defaults with LiteLLM routing + Qwen as model
        model = {
          provider = "custom";
          default = "qwen-chat";
          base_url = litellmUrl;
          api_key = "\${OPENAI_API_KEY}";
          max_context = 262144;
        };

        # Auxiliary models (vision / compression / session_search) → LiteLLM
        auxiliary = {
          vision = {
            provider = "custom";
            model = "qwen-chat";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
          compression = {
            provider = "custom";
            model = "qwen-chat";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
          session_search = {
            provider = "custom";
            model = "qwen-chat";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
        };

        model_aliases.qwen = {
          model = "qwen-chat";
          provider = "custom";
          base_url = litellmUrl;
        };

        agent.max_turns = 60;
      };

      # Override the flake's bundled SOUL with the homelab agent persona.
      soulFile = ./homelab-SOUL.md;
    };

    # BARE-METAL ALTERNATIVE (uncomment + comment the container block above):
    #
    # services.hermes-agent = {
    #   enable = true;
    #   environmentFile = config.sops.secrets."hermes_server/env".path;
    #   apiPort = 8642;
    #   webhookPort = 8644;
    #   telegramAllowedUsers = [ 7729797827 ];
    #   openaiBaseUrl = litellmUrl;
    #   soulFile = ./homelab-SOUL.md;
    #   settings = {
    #     # same overlay as container block above
    #   };
    # };

    # SWAG handles external access; no host-firewall changes.
    networking.firewall.allowedTCPPorts = [];
  };
}
