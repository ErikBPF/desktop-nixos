{
  config,
  pkgs,
  ...
}: let
  palette = config.colorScheme.palette;
in {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    terminal = "ghostty";
    theme = let
      inherit (config.lib.formats.rasi) mkLiteral;
    in {
      "*" = {
        bg = mkLiteral "#${palette.base00}";
        fg = mkLiteral "#${palette.base05}";
        accent = mkLiteral "#${palette.base0D}";
        urgent = mkLiteral "#${palette.base0F}";
        background-color = mkLiteral "transparent";
        text-color = mkLiteral "@fg";
        font = "JetBrainsMono Nerd Font 11";
      };
      window = {
        width = mkLiteral "600px";
        background-color = mkLiteral "@bg";
        border = mkLiteral "2px";
        border-color = mkLiteral "#${palette.base02}";
        border-radius = mkLiteral "10px";
        padding = mkLiteral "16px";
      };
      inputbar = {
        spacing = mkLiteral "8px";
        padding = mkLiteral "8px";
        background-color = mkLiteral "#${palette.base01}";
        border-radius = mkLiteral "8px";
      };
      prompt = {
        enabled = false;
      };
      entry = {
        placeholder = "Search...";
        placeholder-color = mkLiteral "#${palette.base03}";
      };
      listview = {
        lines = 8;
        spacing = mkLiteral "4px";
        padding = mkLiteral "8px 0 0 0";
      };
      element = {
        padding = mkLiteral "8px";
        border-radius = mkLiteral "6px";
        spacing = mkLiteral "8px";
      };
      "element selected" = {
        background-color = mkLiteral "#${palette.base02}";
      };
      element-icon = {
        size = mkLiteral "24px";
      };
      element-text = {
        highlight = mkLiteral "bold #${palette.base0D}";
      };
    };
    extraConfig = {
      show-icons = true;
      drun-display-format = "{name}";
      disable-history = false;
      click-to-exit = true;
    };
  };
}
