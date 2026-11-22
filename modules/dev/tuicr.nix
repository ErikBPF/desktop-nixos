_: {
  flake.modules.home.tuicr = {
    config,
    pkgs,
    ...
  }: let
    toml = pkgs.formats.toml {};

    # Open Code Review (`ocr`) — not in nixpkgs; pinned upstream static
    # release asset (raw binary, so dontUnpack). The /cr skill runs it as an
    # optional machine pre-pass before the human tuicr review. Bump version and
    # hash with `nix-prefetch-url <url>`.
    ocr = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "opencodereview";
      version = "1.14.0";
      src = pkgs.fetchurl {
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
  in {
    home.packages = [pkgs.tuicr ocr];

    home.file.".agents/skills/tuicr".source = "${pkgs.tuicr.src}/skills/tuicr";

    xdg.configFile."tuicr/config.toml".source = toml.generate "tuicr-config.toml" {
      theme_dark = "tokyo-night-storm";
      theme_light = "tokyo-night-day";
      comment_vim = true;
      show_pr_checks = true;
      diff_watch_interval_ms = 1000;
      no_update_check = true;
      username = config.home.username;

      comment_types = [
        {
          id = "issue";
          definition = "must fix before merge";
          color = "red";
        }
        {
          id = "suggestion";
          definition = "non-blocking improvement";
        }
        {
          id = "note";
          label = "question";
          definition = "needs clarification";
        }
        {
          id = "praise";
          definition = "good pattern worth preserving";
        }
      ];
    };
  };
}
