{...}: {
  flake.modules.home.aliases = {...}: {
    # Aliases are consumed by fish.nix and bash.nix via direct import.
    # This module exists as a placeholder for profile composition.
    # The actual alias definitions live in modules/_home-manager/shell/aliases.nix
    # and are imported by the shell modules that need them.
  };
}
