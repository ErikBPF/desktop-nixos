{inputs, ...}: {
  flake.modules.nixos.overlays = _: {
    nixpkgs.overlays = [
      # Exposes pkgs.vscode-marketplace.<publisher>.<name> for declarative
      # VS Code extensions (see modules/dev/vscode.nix).
      inputs.nix-vscode-extensions.overlays.default
      (final: _prev: {
        quickshell = inputs.quickshell.packages.${final.stdenv.hostPlatform.system}.default;
        claude-code = inputs.claude-code-nix.packages.${final.stdenv.hostPlatform.system}.default;
        # 2.3.1 pin: 2.3.2 has broken GL init on Mesa 26.x (see flake.nix input).
        inherit (import inputs.nixpkgs-orca {inherit (final.stdenv.hostPlatform) system;}) orca-slicer;

        # grafatui — Prometheus/Grafana metrics TUI (not in nixpkgs). Built from
        # the GitHub tag (v0.1.10 is GH-only; crates.io tops out at 0.1.9).
        # Consumed by modules/terminal/grafatui.nix.
        grafatui = final.rustPlatform.buildRustPackage rec {
          pname = "grafatui";
          version = "0.1.10";
          src = final.fetchFromGitHub {
            owner = "fedexist";
            repo = "grafatui";
            rev = "v${version}";
            hash = "sha256-bFCq0PzowFF+7CC9HFlJoGbpJ0ldFafBvy8QI4NzOzU=";
          };
          cargoHash = "sha256-7ReVLNtzL5nRXIn327PZ3rE3pnMN21QRYKhUJHEKtPg=";
        };
      })
    ];
  };
}
