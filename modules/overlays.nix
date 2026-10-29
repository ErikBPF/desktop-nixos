{inputs, ...}: {
  flake.modules.nixos.overlays = _: {
    nixpkgs.overlays = [
      # Exposes pkgs.vscode-marketplace.<publisher>.<name> for declarative
      # VS Code extensions (see modules/dev/vscode.nix).
      inputs.nix-vscode-extensions.overlays.default
      (final: _: {
        quickshell = inputs.quickshell.packages.${final.stdenv.hostPlatform.system}.default;
        claude-code = inputs.claude-code-nix.packages.${final.stdenv.hostPlatform.system}.default;
        # 2.3.1 pin: 2.3.2 has broken GL init on Mesa 26.x (see flake.nix input).
        inherit (import inputs.nixpkgs-orca {inherit (final.stdenv.hostPlatform) system;}) orca-slicer;

        # grafatui — Prometheus/Grafana metrics TUI (not in nixpkgs). Built from
        # the GitHub tag (v0.1.11 is GH-only; crates.io tops out at 0.1.9).
        # Consumed by modules/terminal/grafatui.nix.
        grafatui = final.rustPlatform.buildRustPackage rec {
          pname = "grafatui";
          version = "0.1.11";
          src = final.fetchFromGitHub {
            owner = "fedexist";
            repo = "grafatui";
            rev = "v${version}";
            hash = "sha256-dzR+oxBIPNBQuCa6RtjJn7pyMkMQSEMgHf671R7EUPs=";
          };
          cargoHash = "sha256-P38Sto1yC2J5amfagaC+UeffBw1nGUcXaKb2PUnEm2U=";
        };

        # dbx — lightweight database client (Tauri, 100+ engines). Not in
        # nixpkgs: the `dbx` there is the unrelated Databricks CLI. Upstream
        # ships a .deb containing one self-contained binary, so unpack that
        # instead of rebuilding the pnpm/cargo workspace.
        # Consumed by modules/packages/desktop.nix.
        dbx = final.stdenvNoCC.mkDerivation rec {
          pname = "dbx";
          version = "0.6.61";

          src = final.fetchurl {
            url = "https://github.com/t8y2/dbx/releases/download/v${version}/DBX_${version}_amd64.deb";
            hash = "sha256-0e4o6FWLvztKtjQZGtQP30BVCesOtDizJCzyam7Xwek=";
          };

          nativeBuildInputs = [
            final.dpkg
            final.autoPatchelfHook
            final.wrapGAppsHook3
          ];

          buildInputs = [
            final.webkitgtk_4_1
            final.gtk3
            final.libsoup_3
            final.glib
            final.gdk-pixbuf
            final.cairo
            final.pango
            final.dbus
            final.fontconfig
            final.wayland
            # Tray icon is dlopen'd, so autoPatchelf cannot see it.
            final.libayatana-appindicator
          ];

          unpackPhase = ''
            runHook preUnpack
            dpkg-deb -x $src .
            runHook postUnpack
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 usr/bin/dbx $out/bin/dbx
            cp -r usr/share $out/share
            runHook postInstall
          '';

          meta = {
            description = "Lightweight cross-platform database client for 100+ databases";
            homepage = "https://github.com/t8y2/dbx";
            license = final.lib.licenses.asl20;
            mainProgram = "dbx";
            platforms = ["x86_64-linux"];
          };
        };
      })
    ];
  };
}
