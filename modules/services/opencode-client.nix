{
  config,
  self,
  ...
}: {
  flake.modules.nixos.opencode-client = {
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
    sops.secrets."opencode/litellm_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "opencode/litellm_key";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/opencode/litellm_key";
    };
    sops.secrets."opencode/work_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "opencode/work_key";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/opencode/work_key";
    };
    # zen_key = OpenCode account key. Read via `{file:...}` by the direct
    # `opencode-go` provider in modules/dev/opencode.nix. Bypasses the LiteLLM
    # pool; keep the key scoped to Go-capable workspaces.
    sops.secrets."opencode/zen_key" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "opencode/zen_key";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/opencode/zen_key";
    };
    # token = ErikBPF GitHub CLI credential, exported as GH_TOKEN by the zsh
    # snippet in modules/dev/opencode.nix. gh resolves its hosts.yml under
    # $XDG_CONFIG_HOME, which opencode rewrites for its children, so the
    # login stored by `gh auth login` is invisible inside a session. GH_TOKEN
    # outranks hosts.yml, so this makes ErikBPF the account in every session.
    sops.secrets."github/token" = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
      key = "github/token";
      owner = "erik";
      mode = "0400";
      path = "/run/secrets/github/token";
    };
  };
}
