_: {
  # Keyboard-driven browser alongside the GUI brave/firefox. config.py is the
  # SSOT (loadAutoconfig off); base16 chrome theming is enabled via the stylix
  # qutebrowser target in modules/desktop/stylix.nix. Wayland is handled by the
  # session-wide Qt env (stylix targets.qt + the Hyprland portal) — no
  # per-launcher QT_QPA_PLATFORM wrapper (gate G1).
  flake.modules.home.qutebrowser = _: {
    programs.qutebrowser = {
      enable = true;
      loadAutoconfig = false;
      searchEngines = {
        DEFAULT = "https://duckduckgo.com/?q={}";
        nw = "https://mynixos.com/search?q={}";
        gh = "https://github.com/search?q={}&type=repositories";
      };
      settings = {
        content.blocking.enabled = true;
        colors.webpage.preferred_color_scheme = "dark";
        tabs.show = "multiple";
      };
    };
  };
}
