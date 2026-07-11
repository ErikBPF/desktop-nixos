{
  config,
  self,
  ...
}: {
  flake.modules.nixos.laptop-opencode-client = {
    config,
    inputs,
    ...
  }: {
    # Sops secrets carrying the per-consumer keys for opencode CLI. The
    # global opencode config (~/.config/opencode/opencode.json) reads these
    # via `{env:VAR}` substitution, sourced into the user shell from
    # /run/secrets/opencode/* by the zsh snippet in modules/dev/opencode.nix.
    #
    # litellm_key = scoped LiteLLM virtual key (alias `opencode`, $20/day,
    #   model allowlist: qwen-chat + embeddings-qwen3 + the cloud coders).
    #   Minted by `just mint-litellm-keys` via mint-litellm-keys.sh.
    #   Replace master key (full admin) with virtual rotation via the same
    #   script when retiring.
    #
    # zen_key = OPENCODE_GO_KEY for opencode Zen (flat-rate escape-hatch
    #   when LiteLLM is offline). Pulled from discovery .env.sops where the
    #   litellm container also sources it.
    sops.secrets."opencode/litellm_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "opencode/litellm_key";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/opencode/litellm_key";
    };
    sops.secrets."opencode/zen_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "opencode/zen_key";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/opencode/zen_key";
    };
  };
}
