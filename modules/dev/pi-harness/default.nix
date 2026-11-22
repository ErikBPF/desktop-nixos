# Registered as a flake-parts module by `import-tree ./modules`.
# The derivation lives in `_package.nix`, which import-tree skips.
_: {
  perSystem = {pkgs, ...}: {
    packages.pi-harness = pkgs.callPackage ./_package.nix {};
    checks.pi-harness-tests = pkgs.callPackage ./_tests.nix {};
  };
}
