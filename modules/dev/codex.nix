{inputs, ...}: {
  flake.modules.home.codex = {
    config,
    lib,
    pkgs,
    ...
  }: let
    uiPython = pkgs.python3.withPackages (p: [p.tomlkit]);

    # Upstream's Codex marketplace points at main even inside a pinned flake.
    # Pin the plugin source too, rather than only pinning the marketplace file.
    ponytailMarketplace = pkgs.writeTextDir ".agents/plugins/marketplace.json" (builtins.toJSON {
      name = "ponytail";
      interface.displayName = "Ponytail";
      plugins = [
        {
          name = "ponytail";
          source = {
            source = "url";
            url = "https://github.com/DietrichGebert/ponytail.git";
            ref = inputs.ponytail.rev;
          };
          policy = {
            installation = "AVAILABLE";
            authentication = "ON_INSTALL";
          };
          category = "Productivity";
        }
      ];
    });
    # rtk (Rust Token Killer) — not in nixpkgs; pinned upstream static-musl
    # release (single-file tarball needs dontUnpack). Bump version + hash via
    # `nix-prefetch-url <url>`. Codex-profile and opencode's rtk.ts plugin
    # both call this binary.
    rtk = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "rtk";
      version = "0.48.0";
      src = pkgs.fetchurl {
        url = "https://github.com/rtk-ai/rtk/releases/download/v${finalAttrs.version}/rtk-x86_64-unknown-linux-musl.tar.gz";
        hash = "sha256-5OZQ+hZ3wN4vaDmmBA17F/MS0y8WPEArda9w6eWvGpE=";
      };
      dontUnpack = true;
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        tar xzf $src
        install -m755 rtk $out/bin/rtk
        runHook postInstall
      '';
    });
  in {
    imports = [inputs.codex-flake.homeManagerModules.withPackage];

    programs.codex-profile = {
      enable = true;
      package.enable = true;
      rtk.enable = true;
      rtk.package = rtk;
      style.enable = true;
      agents.extraText = builtins.readFile ./agent-policy.md;
    };

    home.packages = [(lib.hiPrio rtk)];

    home.sessionVariables.GRAPHIFY_NO_TIPS = "1";

    # graphify harness skill, vendored from `graphify install --platform codex`
    # output (graphifyy uv-tool binary v0.9.53). Keep the vendored copy in sync
    # when the uv tool is bumped; the binary itself stays imperative (not in
    # nixpkgs).
    home.file.".codex/skills/graphify".source = ./graphify-skills/codex;

    # Vendored BMAD skills used by rv's editorial + adversarial passes. The
    # _bmad script machinery is replaced by self-contained fallbacks in the
    # skill sources.
    home.file.".agents/skills/bmad-editorial-review".source = ./codex-skills/bmad-editorial-review;
    home.file.".agents/skills/bmad-party-mode".source = ./codex-skills/bmad-party-mode;
    # Vendored caveman family + TDD skill (formerly unmanaged dirs in
    # ~/.agents/skills). Codex can disable the prose skills in mutable config;
    # its global response style is managed separately above.
    home.file.".agents/skills/cavecrew".source = ./codex-skills/cavecrew;
    home.file.".agents/skills/caveman".source = ./codex-skills/caveman;
    home.file.".agents/skills/caveman-commit".source = ./codex-skills/caveman-commit;
    home.file.".agents/skills/caveman-compress".source = ./codex-skills/caveman-compress;
    home.file.".agents/skills/caveman-help".source = ./codex-skills/caveman-help;
    home.file.".agents/skills/caveman-review".source = ./codex-skills/caveman-review;
    home.file.".agents/skills/caveman-stats".source = ./codex-skills/caveman-stats;
    home.file.".agents/skills/test-driven-development".source = ./codex-skills/test-driven-development;
    home.file.".agents/skills/codehero".source = ./codex-skills/codehero;
    home.file.".agents/skills/grill".source = ./codex-skills/grill;
    home.file.".agents/skills/ip".source = ./codex-skills/ip;
    home.file.".agents/skills/map".source = ./codex-skills/map;
    home.file.".agents/skills/party".source = ./codex-skills/party;
    home.file.".agents/skills/pl".source = ./codex-skills/pl;
    home.file.".agents/skills/rv".source = ./codex-skills/rv;

    home.activation.configureCodexUI = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${uiPython}/bin/python ${../../scripts/configure-codex-ui.py} "$HOME/.codex/config.toml"
    '';

    home.activation.installCodexPonytail = lib.hm.dag.entryAfter ["installPackages"] ''
      export PATH=${lib.makeBinPath [pkgs.git]}:$PATH
      old_marketplace=$(${lib.getExe config.programs.codex-profile.package.package} plugin marketplace list --json |
        ${lib.getExe pkgs.jq} -r '.marketplaces[] | select(.name == "ponytail") | .root')
      if [[ -n "$old_marketplace" && "$old_marketplace" != "${ponytailMarketplace}" ]]; then
        run ${lib.getExe config.programs.codex-profile.package.package} plugin marketplace remove ponytail
      fi
      run ${lib.getExe config.programs.codex-profile.package.package} plugin marketplace add ${ponytailMarketplace}
      run ${lib.getExe config.programs.codex-profile.package.package} plugin add ponytail@ponytail
    '';
  };
}
