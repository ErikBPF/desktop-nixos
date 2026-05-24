{
  config,
  self,
  ...
}: {
  flake.modules.nixos.laptop-hermes-client = {
    config,
    inputs,
    ...
  }: {
    # Sops secret carrying Discovery's API_SERVER_KEY. The laptop's hermes
    # CLI uses this to authenticate against Discovery's /v1 OpenAI-compatible
    # API gateway (hermes.homelab.pastelariadev.com).
    sops.secrets."hermes_agent/client_api_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "hermes_agent/client_api_key";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/hermes_agent_client_api_key";
    };
  };
}
