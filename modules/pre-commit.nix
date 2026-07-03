{inputs, ...}: {
  # Declarative pre-commit hooks — mechanically enforce the Defensive Commit
  # Rules (fmt, lint, no secrets) instead of relying on discipline. Installed
  # automatically on `direnv`/`nix develop` entry (see modules/dev-shell.nix),
  # and also run as a flake check in CI.
  imports = [inputs.git-hooks.flakeModule];

  perSystem = {
    pre-commit.settings.hooks = {
      alejandra.enable = true; # nix fmt (same as `just fmt`)
      statix = {
        enable = true; # nix lint (same as `just lint`)
        settings.config = ".statix.toml"; # honor repo config (disables repeated_keys, ignores)
      };
      ripsecrets.enable = true; # block staged secrets
    };
  };
}
