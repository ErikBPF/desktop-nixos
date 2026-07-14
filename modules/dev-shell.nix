{
  perSystem = {
    pkgs,
    config,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        pkgs.statix
        pkgs.just
        pkgs.alejandra
        pkgs.bats
        pkgs.shellcheck
      ];
      # Installs the git pre-commit hook (see modules/pre-commit.nix) on entry.
      shellHook = config.pre-commit.installationScript;
    };
  };
}
