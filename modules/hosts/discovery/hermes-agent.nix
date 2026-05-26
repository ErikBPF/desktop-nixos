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

    # Sops secret carrying the hermes env dotenv. Lives under the
    # consolidated `hermes_agent.server_env` block in
    # secrets/sops/secrets.yaml.
    sops.secrets."hermes_agent/server_env" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      format = "yaml";
      key = "hermes_agent/server_env";
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
      hostSecretsPath = config.sops.secrets."hermes_agent/server_env".path;
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
          # Must match Orion's llama-chat LLAMA_CTX (servarr/machines/orion/.env
          # → LLAMA_CTX=196608, default in ai-models.yml). Setting this higher
          # than the served context causes prompts >196608 tokens to be
          # rejected or silently truncated by llama-server, with no clean
          # error path back to the agent.
          max_context = 196608;
        };

        # Auxiliary models — all routed through LiteLLM. Audio (STT/TTS) and
        # the new embeddings model land on Kepler's ai-serving stack; vision
        # is routed to Qwen2.5-VL on Orion once wired (see litellm_config.yaml).
        auxiliary = {
          vision = {
            provider = "custom";
            model = "vision-qwen2vl";
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
          transcription = {
            provider = "custom";
            model = "whisper-pt-br";
            base_url = litellmUrl;
            api_key = "\${OPENAI_API_KEY}";
          };
          tts = {
            # Canonical PT-BR TTS — Piper, hit directly on kepler:8002.
            #
            # We intentionally bypass LiteLLM here: its proxy's `audio_speech`
            # route calls `Router.aspeech(**data)` straight from the request
            # body, and `Router.aspeech()` has `voice` as a required
            # positional argument. Callers (including hermes-agent) that
            # omit `voice` get a 500 before any pre_call_hook can fix it.
            # piper-openai's shim defaults the voice when missing, so the
            # direct hit is the path of least friction. Cost tracking via
            # LiteLLM is sacrificed for this single route until upstream
            # accepts a request-body default.
            provider = "custom";
            model = "piper";
            base_url = "http://kepler:8002/v1";
            api_key = "sk-no-key-required";
          };
          embeddings = {
            provider = "custom";
            model = "embeddings-qwen3";
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
    #   environmentFile = config.sops.secrets."hermes_agent/server_env".path;
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
