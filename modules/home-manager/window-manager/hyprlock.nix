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
      general = {
        disable_loading_bar = true;
        no_fade_in = false;
      };
      auth = {
        fingerprint.enabled = true;
      };
    };
    extraConfig = ''
# BACKGROUND
background {
    monitor =
    path = ${selected_wallpaper_path}
    blur_passes = 3
    contrast = 0.8916
    brightness = 0.8172
    vibrancy = 0.1696
    vibrancy_darkness = 0.0
}

# GENERAL
general {
    no_fade_in = false
    grace = 0
    disable_loading_bar = false
}

# TIME
label {
    monitor =
     text = cmd[update:1000] echo "$(date +"%H:%M")"
    color = ${foregroundRgb}
    font_size = 120
    font_family = JetBrainsMono Nerd Font Bold
    position = 0, -140
    halign = center
    valign = top
}

# DAY-DATE-MONTH
label {
    monitor =
    text = cmd[update:1000] echo "<span>$(date '+%A, %d %B')</span>"
    color = rgba(255, 255, 255, 0.6)
    font_size = 30
    font_family = JetBrainsMono Nerd Font Bold
    position = 0, 200
    halign = center
    valign = center
}

# LOGO
label {
    monitor =
    text = "" 
    color = rgba(255, 255, 255, 0.65)
    font_size = 120
    position = 0, 60
    halign = center
    valign = center
}

# USER
label {
    monitor =
    text = Hello, $USER
    color = rgba(255, 255, 255, .65)
    font_size = 25
    font_family = JetBrainsMono Nerd Font Bold
    position = 0, -70
    halign = center
    valign = center
}

# INPUT FIELD
input-field {
    monitor =
    size = 290, 60
    outline_thickness = 2
    dots_size = 0.2 # Scale of input-field height, 0.2 - 0.8
    dots_spacing = 0.2 # Scale of dots' absolute size, 0.0 - 1.0
    dots_center = true
    outer_color = rgba(0, 0, 0, 0)
    inner_color = rgba(60, 56, 54, 0.35)
    font_color = rgb(200, 200, 200)
    fade_on_empty = false
    font_family = JetBrainsMono Nerd Font Bold
    placeholder_text = <i><span foreground="##ffffff99">••••••••</span></i>
    hide_input = false
    position = 0, -140
    halign = center
    valign = center
}

# CURRENT SONG
# label {
#     monitor =
#     text = cmd[update:1000] echo "$(~/.config/hypr/Scripts/songdetail.sh)" 
#     color = ${foregroundMutedRgb}
#     font_size = 16
#     font_family = JetBrainsMono Nerd Font
#     position = 0, 80
#     halign = center
#     valign = bottom
# }

# Reboot
label {
    monitor =
    text = "󰜉"
    color = rgba(255, 255, 255, 0.6)
    font_size = 50
    onclick = reboot now
    position = 0, 100
    halign = center
    valign = bottom
}

# Power off
label {
    monitor =
    text = "󰐥"
    color = rgba(255, 255, 255, 0.6)
    font_size = 50
    onclick = shutdown now
    position = 820, 100
    halign =left 
    valign = bottom
}

# Suspend
label {
    monitor =
    text = "󰤄"
    color = rgba(255, 255, 255, 0.6)
    font_size = 50
    onclick = systemctl suspend
    position = -820, 100
    halign = right
    valign = bottom
}
    '';
    };
}
