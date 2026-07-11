{
  config,
  inputs,
  ...
}: let
  inherit (config) domain; # flake-parts top-level option (meta.nix)
in {
  flake.modules.home.hermes-agent = {
    pkgs,
    lib,
    config,
    ...
  }: let
    apiKeyPath = "/run/secrets/hermes_agent_client_api_key";
    discoveryApiUrl = "https://hermes.homelab.${domain}/v1";
    system = pkgs.stdenv.hostPlatform.system;
  in {
    imports = [inputs.hermes-flake.homeManagerModules.default];

    # Fast one-shot wrapper — bypasses ~5s of local hermes agent init for
    # simple Q&A. Goes straight to Discovery's API gateway via curl.
    # Usage:  hq "what's the weather"
    # Use `hermes` itself when you need sessions / tools / memory.
    programs.zsh.initContent = ''
      # quick one-shot prompt to Discovery's hermes API
      hq() {
        local prompt="$*"
        if [[ -z "$prompt" ]]; then
          echo "usage: hq <prompt>" >&2
          return 1
        fi
        if [[ -z "$OPENAI_API_KEY" || -z "$OPENAI_BASE_URL" ]]; then
          echo "missing OPENAI_API_KEY or OPENAI_BASE_URL" >&2
          return 2
        fi
        local payload
        payload=$(jq -n --arg p "$prompt" \
          '{model:"hermes-agent",messages:[{role:"user",content:$p}],max_tokens:512}')
        curl -sS --max-time 60 \
          -H "Authorization: Bearer $OPENAI_API_KEY" \
          -H "Content-Type: application/json" \
          -d "$payload" \
          "$OPENAI_BASE_URL/chat/completions" \
          | jq -r '.choices[0].message.content // .error.message // .'
      }
    '';

    programs.hermes-agent = {
      enable = true;
      # Avoid upstream module default using deprecated `pkgs.system`.
      package = inputs.hermes-flake.packages.${system}.hermes-agent.withExtras config.programs.hermes-agent.extras;

      # Keep user's existing ~/.hermes (migrated state lives here)
      dataDir = "/home/${config.home.username or "erik"}/.hermes";
      configDir = "/home/${config.home.username or "erik"}/.hermes";

      # API_SERVER_KEY rendered by sops to apiKeyPath.
      # Exported into the shell as OPENAI_API_KEY so hermes CLI uses it.
      secrets.openaiApiKeyFile = apiKeyPath;

      # Fast one-shot alias — bypasses the local hermes agent init (~5s
      # saving). Goes straight to Discovery's API server.
      # Usage: hq "what's the weather"
      # Falls back to `hermes -z` only when a session / tools / memory are
      # needed.
      extraEnvironment = {
        # Route model calls through Discovery's hermes API gateway.
        # Chain: laptop hermes CLI (local) → Discovery API → LiteLLM → Orion.
        # NOTE: this only delegates LLM inference. The hermes-agent logic
        # itself still runs locally in-process; only model calls are remote.
        OPENAI_BASE_URL = discoveryApiUrl;
        HERMES_DEFAULT_MODEL = "qwen-chat";

        # Laptop is a thin client — turn off the local gateways. They bind
        # 127.0.0.1:8642 + 127.0.0.1:8644 by default which is dead weight
        # for an interactive CLI session. The "real" gateways live on
        # Discovery (Telegram, Discord, webhook, api_server).
        API_SERVER_ENABLED = "false";
        WEBHOOK_ENABLED = "false";

        # Skip the local node-runtime bootstrap (browser tools etc.) —
        # heavy tooling runs server-side. Saves ~0.8s per startup.
        HERMES_SKIP_NODE_BOOTSTRAP = "1";

        # Suppress noisy startup output.
        HERMES_QUIET = "1";
      };
    };
  };
}
