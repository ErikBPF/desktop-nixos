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
    apiKeyPath = "/run/secrets/hermes_client_api_key";
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
        # Route all model calls through Discovery's hermes API gateway.
        # Chain: laptop hermes CLI → Discovery hermes API → LiteLLM → backend.
        OPENAI_BASE_URL = discoveryApiUrl;
        HERMES_DEFAULT_MODEL = "qwen-chat";
      };
    };
  };
}
