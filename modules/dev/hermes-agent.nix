{
  config,
  inputs,
  ...
}: {
  flake.modules.home.hermes-agent = {
    pkgs,
    lib,
    config,
    ...
  }: let
    apiKeyPath = "/run/secrets/hermes_agent_client_api_key";
    discoveryApiUrl = "https://hermes.homelab.pastelariadev.com/v1";
  in {
    imports = [inputs.hermes-flake.homeManagerModules.default];

    programs.hermes-agent = {
      enable = true;
      # No explicit `package` — let the HM module compute it from `extras`
      # via the flake's `withExtras` passthru. Add `extras = [...]` here
      # to pull in optional dep groups (voice, anthropic, mcp, etc.).

      # Keep user's existing ~/.hermes (migrated state lives here)
      dataDir = "/home/${config.home.username or "erik"}/.hermes";
      configDir = "/home/${config.home.username or "erik"}/.hermes";

      # API_SERVER_KEY rendered by sops to apiKeyPath.
      # Exported into the shell as OPENAI_API_KEY so hermes CLI uses it.
      secrets.openaiApiKeyFile = apiKeyPath;

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
