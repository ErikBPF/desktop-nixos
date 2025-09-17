{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  palette = config.colorScheme.palette;
  convert = inputs.nix-colors.lib.conversions.hexToRGBString;
  selected_wallpaper_path = "~/Pictures/Wallpapers/wallpaper.png";

  backgroundRgb = "rgba(${convert ", " palette.base00}, 0.8)";
  surfaceRgb = "rgb(${convert ", " palette.base02})";
  foregroundRgb = "rgb(${convert ", " palette.base05})";
  foregroundMutedRgb = "rgb(${convert ", " palette.base04})";
in {
  programs.hyprlock = {
    enable = true;
    settings = {
      # BACKGROUND
      background = {
        monitor = "";
        path = selected_wallpaper_path;
        blur_passes = 2;
        contrast = 0.8916;
        brightness = 0.8172;
        vibrancy = 0.1696;
        vibrancy_darkness = 0.0;
      };

      # GENERAL
      general = {};

      # Day
      label = {
        monitor = "";
        text = "cmd[update:1000] echo -e \"$(date +\"%A\")\"";
        color = foregroundRgb;
        font_size = 90;
        font_family = "JetBrainsMono Nerd Font";
        position = "0, 350";
        halign = "center";
        valign = "center";
      };

      # Date-Month
      label = {
        monitor = "";
        text = "cmd[update:1000] echo -e \"$(date +\"%d %B\")\"";
        color = foregroundRgb;
        font_size = 40;
        font_family = "JetBrainsMono Nerd Font";
        position = "0, 250";
        halign = "center";
        valign = "center";
      };

      # Time
      label = {
        monitor = "";
        text = "cmd[update:1000] echo \"<span>$(date +\"- %I:%M -\")</span>\"";
        color = foregroundRgb;
        font_size = 20;
        font_family = "JetBrainsMono Nerd Font";
        position = "0, 190";
        halign = "center";
        valign = "center";
      };

      # Profie-Photo
      label = {
        monitor = "";
        text = "";
        color = "rgba(255, 255, 255, 0.65)";
        font_size = 120;
        position = "0, 40";
        halign = "center";
        valign = "center";
      };
      

      # USER-BOX
      shape = {
        monitor = "";
        size = "300, 60";
        color = "rgba(255, 255, 255, .1)";
        rounding = -1;
        border_size = 0;
        border_color = "rgba(255, 255, 255, 0)";
        rotate = 0;
        xray = false; # if true, make a "hole" in the background (rectangle of specified size, no rotation)
        position = "0, -130";
        halign = "center";
        valign = "center";
      };

      # USER
      label = {
        monitor = "";
        text = "Hello, $USER";
        color = foregroundRgb;
        font_size = 18;
        font_family = "JetBrainsMono Nerd Font";
        position = "0, -130";
        halign = "center";
        valign = "center";
      };

      # INPUT FIELD
      input-field = {
        monitor = "";
        size = "300, 60";
        outline_thickness = 2;
        dots_size = 0.2; # Scale of input-field height, 0.2 - 0.8
        dots_spacing = 0.2; # Scale of dots' absolute size, 0.0 - 1.0
        dots_center = true;
        outer_color = foregroundRgb;
        inner_color = surfaceRgb;
        font_color = foregroundRgb;
        fade_on_empty = false;
        font_family = "JetBrainsMono Nerd Font";
        placeholder_text = "  Enter Password 󰈷 ";
        hide_input = false;
        position = "0, -210";
        halign = "center";
        valign = "center";
      };

      # Reboot
      label = {
        monitor = "";
        text = "󰜉";
        color = foregroundMutedRgb;
        font_size = 50;
        onclick = "reboot now";
        position = "0, 100";
        halign = "center";
        valign = "bottom";
      };

      # Power off
      label = {
        monitor = "";
        text = "󰐥";
        color = foregroundMutedRgb;
        font_size = 50;
        onclick = "shutdown now";
        position = "820, 100";
        halign = "left";
        valign = "bottom";
      };

      # Suspend
      label = {
        monitor = "";
        text = "󰤄";
        color = foregroundMutedRgb;
        font_size = 50;
        onclick = "systemctl suspend";
        position = "-820, 100";
        halign = "right";
        valign = "bottom";
      };
    };
  };
}
