{inputs, ...}: {
  flake.modules.nixos.overlays = _: {
    nixpkgs.overlays = [
      (final: _prev: {
        quickshell = inputs.quickshell.packages.${final.stdenv.hostPlatform.system}.default;
        claude-code = inputs.claude-code-nix.packages.${final.stdenv.hostPlatform.system}.default;
        # 2.3.1 pin: 2.3.2 has broken GL init on Mesa 26.x (see flake.nix input).
        inherit (import inputs.nixpkgs-orca {inherit (final.stdenv.hostPlatform) system;}) orca-slicer;
      })
    ];
  };
}
