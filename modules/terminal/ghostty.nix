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
        # Reuse one process for every window. The default (`desktop`) only
        # dedupes D-Bus/.desktop launches, so a plain `ghostty` from a Hyprland
        # exec keybind forks a fresh process each time and pays the full GTK4 +
        # OpenGL + Nerd-Font cold start (~1.8s). With `true` only the first
        # terminal is cold; later windows share the instance (~0.5s). The
        # spotify TUI in hyprland.nix passes --gtk-single-instance=false
        # explicitly, so it keeps its own process.
        gtk-single-instance = true;
      };
    };
  };
}
