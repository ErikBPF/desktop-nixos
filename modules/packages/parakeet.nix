{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {inherit system;};
  in {
    packages.parakeet-cpp = pkgs.callPackage ./_parakeet-cpp.nix {};
  };
}
