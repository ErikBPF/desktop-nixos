{inputs, ...}: {
  flake.modules.nixos.overlays = _: {
    nixpkgs.overlays = [
      (final: _prev: {
        quickshell = inputs.quickshell.packages.${final.stdenv.hostPlatform.system}.default;
      })
    ];
  };
}
