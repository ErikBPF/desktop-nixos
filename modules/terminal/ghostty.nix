_: {
  flake.modules.home.ghostty = _: {
    programs.ghostty = {
      enable = true;
      enableFishIntegration = true;
      settings = {
        font-family = "JetBrainsMono Nerd Font";
        font-size = 10;
        freetype-load-flags = "no-force-autohint";
        theme = "TokyoNight Night";
        confirm-close-surface = false;
      };
    };
  };
}
