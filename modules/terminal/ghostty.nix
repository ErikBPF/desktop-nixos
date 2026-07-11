_: {
  flake.modules.home.ghostty = _: {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        # Pin the shell to the active system's zsh instead of inheriting $SHELL.
        # A login-shell change (e.g. the fish→zsh migration) does not propagate
        # into an already-running graphical session's $SHELL, so without this a
        # switch that removes the old shell strands every new terminal.
        command = "/run/current-system/sw/bin/zsh";
        font-family = "JetBrainsMono Nerd Font";
        font-size = 10;
        freetype-load-flags = "no-force-autohint";
        theme = "TokyoNight Night";
        confirm-close-surface = false;
      };
    };
  };
}
