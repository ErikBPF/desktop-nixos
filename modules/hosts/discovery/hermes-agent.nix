{
  config,
  inputs,
  self,
  ...
}: let
  inherit (config) domain; # flake-parts top-level option (meta.nix)
in {
  flake.modules.nixos.discovery-hermes-agent = {
    config,
    lib,
    pkgs,
    ...
  }: let
    litellmUrl = "https://litellm.homelab.${domain}/v1";
  in {
    imports = [
      # Pick ONE of the two below:
      inputs.hermes-flake.nixosModules.hermes-agent-container
      # inputs.hermes-flake.nixosModules.default  # bare-metal alternative
    ];

    # sops-install-secrets runs on the *host* during activation and chowns the
    # decrypted secret to `hermes`. That user only exists inside the nspawn
    # container (uid/gid 10000, created by hermes-flake's inner module), so the
    # chown fails on the host with "unknown user hermes". Mirror the same
    # uid/gid on the host: with shared-network nspawn and no user namespacing
    # the host uid == container uid, so this both satisfies the chown and keeps
    # the read-only bind-mounted secret readable as uid 10000 inside the guest.
    users.groups.hermes.gid = 10000;
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      uid = 10000;
    };

    # The container read-write bind-mounts hostDataDir into the guest as
    # /var/lib/hermes-agent. systemd-nspawn refuses to start if the host path is
    # missing ("Failed to clone /var/lib/hermes-agent: No such file or
    # directory"), so create it up front owned by the same uid/gid the guest
    # runs hermes as.
    systemd.tmpfiles.rules = [
      "d /var/lib/hermes-agent 0750 hermes hermes -"
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

      # YOLO: bypass the gateway's dangerous-command approval prompts. The
      # config-level `approvals.mode = "off"` below only covers the non-command
      # approval paths; the shell-command gate keys off HERMES_YOLO_MODE (frozen
      # at process import). hermes' hardcoded catastrophic floor (rm -rf /, mkfs,
      # shutdown, …) still blocks regardless.
      extraEnvironment.HERMES_YOLO_MODE = "1";

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
            # Canonical PT-BR TTS — Piper, routed through LiteLLM. The proxy
            # monkey-patches Router.aspeech in sitecustomize.py so requests
            # without `voice` no longer 500. See
            # servarr/machines/discovery/config/litellm/sitecustomize.py.
            provider = "custom";
            model = "tts-pt-br";
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

        # YOLO / permanent auto-approve. hermes gates only DANGEROUS commands;
        # the per-prompt "session" choice and the runtime "/yolo" toggle are
        # in-memory and lost on restart — only an explicit "always" persists
        # (written to /var/lib/hermes-agent/config.yaml). Setting the approval
        # mode off here makes auto-approve permanent and declarative. A
        # hardcoded catastrophic floor in hermes still blocks truly destructive
        # ops regardless of this setting.
        approvals.mode = "off";
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
