{inputs, ...}: {
  flake.modules.nixos.overlays = {...}: {
    nixpkgs.overlays = [
      (final: _prev: {
        quickshell = inputs.quickshell.packages.${final.system}.default;
      })
    ];
  };
}
