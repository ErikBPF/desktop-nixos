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
        pkgs.sops
        pkgs.age
        (pkgs.python3.withPackages (p: [p.pyyaml p.pip]))
      ];
      # Installs the git pre-commit hook (see modules/pre-commit.nix) on entry.
      shellHook = config.pre-commit.installationScript;
    };
  };
}
