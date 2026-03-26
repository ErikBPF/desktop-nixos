{...}: {
  flake.modules.home.hyprlock = {
    config,
    inputs,
    ...
  }: let
    palette = config.colorScheme.palette;
    convert = inputs.nix-colors.lib.conversions.hexToRGBString;
    selected_wallpaper_path = "~/Pictures/Wallpapers/wallpaper.png";
    foregroundRgb = "rgb(${convert ", " palette.base05})";
  in {
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = true;
          no_fade_in = false;
          screencopy_mode = 0;
        };
        auth.fingerprint.enabled = true;
      };
      extraConfig = ''
        background {
            monitor =
            path = ${selected_wallpaper_path}
            blur_passes = 1
            contrast = 0.8916
            brightness = 0.8172
            vibrancy = 0.1696
            vibrancy_darkness = 0.0
        }

        general {
            no_fade_in = false
            grace = 0
            disable_loading_bar = false
        }

        label {
            monitor =
             text = cmd[update:1000] echo "$(date +"%H:%M")"
            color = ${foregroundRgb}
            font_size = 140
            font_family = JetBrainsMono Nerd Font Bold
            position = 0, -120
            halign = center
            valign = top
        }

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

        input-field {
            monitor =
            size = 290, 60
            outline_thickness = 2
            dots_size = 0.2
            dots_spacing = 0.2
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
      '';
    };
  };
}
