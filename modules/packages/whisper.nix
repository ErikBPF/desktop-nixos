{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {inherit system;};
  in {
    packages.whisper-cpp-vulkan = pkgs.callPackage ./_whisper-cpp.nix {};
  };
}
