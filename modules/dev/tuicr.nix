_: {
  flake.modules.home.tuicr = {
    config,
    pkgs,
    ...
  }: let
    toml = pkgs.formats.toml {};
  in {
    home.packages = [pkgs.tuicr];

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
