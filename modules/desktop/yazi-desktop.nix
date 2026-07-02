_: {
  # Desktop-only yazi extras. Base yazi (profile-base, fleet-wide incl. servers)
  # stays a lean TUI; these bits pull GUI deps (ripdrag/GTK4) + ghostty, so they
  # live here and load only via profile-desktop.
  flake.modules.home.yazi-desktop = {pkgs, ...}: {
    # ripdrag: the drag plugin shells out to it (Wayland-native drag source).
    home.packages = [pkgs.ripdrag];

    programs.yazi = {
      plugins.drag = pkgs.yaziPlugins.drag;

      flavors."tokyo-night" = pkgs.fetchFromGitHub {
        owner = "BennyOe";
        repo = "tokyo-night.yazi";
        rev = "8e6296f14daff24151c736ebd0b9b6cd89b02b03";
        hash = "sha256-LArhRteD7OQRBguV1n13gb5jkl90sOxShkDzgEf3PA0=";
      };
      theme.flavor = {
        dark = "tokyo-night";
        light = "tokyo-night";
      };

      keymap.mgr.prepend_keymap = [
        {
          on = ["<C-d>"];
          run = "plugin drag";
          desc = "Drag & drop selection to GUI apps (ripdrag)";
        }
        {
          on = ["<C-t>"];
          run = "shell 'ghostty' --orphan";
          desc = "Open a terminal in the current folder";
        }
      ];
    };
  };
}
