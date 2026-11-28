{inputs, ...}: {
  flake.modules.nixos.overlays = _: {
    nixpkgs.overlays = [
      # Exposes pkgs.vscode-marketplace.<publisher>.<name> for declarative
      # VS Code extensions (see modules/dev/vscode.nix).
      inputs.nix-vscode-extensions.overlays.default
      (final: _: {
        quickshell = inputs.quickshell.packages.${final.stdenv.hostPlatform.system}.default;
        claude-code = inputs.claude-code-nix.packages.${final.stdenv.hostPlatform.system}.default;

        # opencodereview — Alibaba's `ocr` review CLI (not in nixpkgs). The
        # upstream release asset is a static Go binary, so no patching is
        # needed. Used by the workstation /cr pre-pass and by the Discovery
        # review collector.
        opencodereview = final.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "opencodereview";
          version = "1.14.0";
          src = final.fetchurl {
            url = "https://github.com/alibaba/open-code-review/releases/download/v${finalAttrs.version}/opencodereview-linux-amd64";
            hash = "sha256-P6+He7eHICad0hUhWrfPR0G/GI4WO48YASy+LTujA30=";
          };
          dontUnpack = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 $src $out/bin/ocr
            runHook postInstall
          '';
        });

        # pqnld — typed decisions over an OpenAI-compatible endpoint (our fork
        # branch: descriptor alphabets + certified partial readout). Consumed by
        # modules/hosts/kepler/pqnld.nix.
        pqnld = let
          src = final.fetchFromGitHub {
            owner = "ErikBPF";
            repo = "pqnld";
            rev = "16f6074df24f34dca1b690da1409e10ecd408077";
            hash = "sha256-JLgx11OkdPnY7aSgO2PBK72opH/ercO7ksXHNcYFNDc=";
          };
        in
          final.rustPlatform.buildRustPackage {
            pname = "pqnld";
            version = "0.4.0";
            inherit src;
            # Verified against this pin: the archive unpacks to `source/`, so the
            # crate directory is `source/sidecar-rs`. Bare `sidecar-rs` fails
            # unpackPhase with `chmod: cannot access 'sidecar-rs'`.
            sourceRoot = "${src.name}/sidecar-rs";
            cargoHash = "sha256-0v6goKH1QALRCkgkqbKniISByjlc2TYihtqXUYCe5+8=";
          };

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
          # zstd-sys probes for libzstd through pkg-config when one is on PATH.
          nativeBuildInputs = [final.pkg-config];
          buildInputs = [final.zstd];
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
