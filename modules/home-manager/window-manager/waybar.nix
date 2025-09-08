{
  config,
  pkgs,
  inputs,
  ...
}: let
  palette = config.colorScheme.palette;
  convert = inputs.nix-colors.lib.conversions.hexToRGBString;
  backgroundRgb = "rgb(${convert ", " palette.base00})";
  foregroundRgb = "rgb(${convert ", " palette.base05})";
in {
  home.file = {
    ".config/waybar/" = {
      source = ../../../config/waybar;
      recursive = true;
    };
    ".config/waybar/theme.css" = {
      text = ''
        @define-color background ${backgroundRgb};
        * {
          color: ${foregroundRgb}; 
        }

        window#waybar {
          background-color: ${backgroundRgb};
        }
      '';
    };
  };

  programs.waybar = {
    enable = true;
    settings = [
      {
        layer = "top";
        position = "top";
        height = 26;
        spacing = 0; # To match style.css
        modules-left = [
          "custom/launch_wofi"
          "hyprland/workspaces"
          "hyprland/window"
        ];
        modules-center = [
          "custom/lock_screen"
          "custom/updates"
          "clock"
        ];
        modules-right = [
          "cpu"
          "memory"
          "temperature"
          "disk"
          "backlight"
          "battery"
          "pulseaudio"
          "pulseaudio#microphone"
          "tray"
          "custom/power_btn"
        ];

        "hyprland/window" = {
          format = "{}";
        };

        "custom/launch_wofi" = {
          format = "";
          on-click = "pkill wofi; wofi -n";
          tooltip = false;
        };

        "custom/lock_screen" = {
          format = "";
          on-click = "sh -c '(sleep 0.5s; swaylock)' & disown";
          tooltip = false;
        };

        "custom/power_btn" = {
          format = "";
          on-click = "sh -c '(sleep 0.5s; wlogout --protocol layer-shell)' & disown";
          tooltip = false;
        };

        cpu = {
          interval = 10;
          format = " {usage}%";
          "max-length" = 10;
          on-click = "ghostty --start-as=fullscreen --title btop sh -c 'btop'";
        };

        disk = {
          interval = 30;
          format = "󰋊 {percentage_used}%";
          path = "/";
          tooltip = true;
          "tooltip-format" = "HDD - {used} used out of {total} on {path} ({percentage_used}%)";
          on-click = "ghostty --start-as=fullscreen --title btop sh -c 'btop'";
        };

        memory = {
          interval = 30;
          format = " {}%";
          "max-length" = 10;
          tooltip = true;
          "tooltip-format" = "Memory - {used:0.1f}GB used";
          on-click = "ghostty --start-as=fullscreen --title btop sh -c 'btop'";
        };

        "custom/updates" = {
          format = "{}";
          exec = "~/.config/waybar/scripts/update-sys";
          on-click = "~/.config/waybar/scripts/update-sys update";
          interval = 300;
          tooltip = true;
        };

        "hyprland/workspaces" = {
          "disable-scroll" = true;
          "all-outputs" = true;
          on-click = "activate";
          "persistent_workspaces" = {
            "1" = [];
            "2" = [];
            "3" = [];
            "4" = [];
            "5" = [];
            "6" = [];
            "7" = [];
            "8" = [];
            "9" = [];
            "10" = [];
          };
        };

        tray = {
          "icon-size" = 18;
          spacing = 10;
        };

        clock = {
          format = "{:%d/%m/%Y - %H:%M}";
          tooltip = true;
          "tooltip-format" = "{: %A, %e %B %Y}";
        };

        backlight = {
          device = "intel_backlight";
          format = "{icon} {percent}%";
          "format-icons" = [ "󰃞" "󰃟" "󰃠"];
          "on-scroll-up" = "brightnessctl set 1%+";
          "on-scroll-down" = "brightnessctl set 1%-";
          "min-length" = 6;
        };

   battery = {
          interval = 5;
          format = "{capacity}% {icon}";
          format-discharging = "{icon}";
          format-charging = "{icon}";
          format-plugged = "";
          format-icons = {
            charging = [
              "󰢜"
              "󰂆"
              "󰂇"
              "󰂈"
              "󰢝"
              "󰂉"
              "󰢞"
              "󰂊"
              "󰂋"
              "󰂅"
            ];
            default = [
              "󰁺"
              "󰁻"
              "󰁼"
              "󰁽"
              "󰁾"
              "󰁿"
              "󰂀"
              "󰂁"
              "󰂂"
              "󰁹"
            ];
          };
          format-full = "Charged ";
          tooltip-format-discharging = "{power:>1.0f}W↓ {capacity}%";
          tooltip-format-charging = "{power:>1.0f}W↑ {capacity}%";
          states = {
            warning = 20;
            critical = 10;
          };
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          "format-muted" = "";
          "on-click" = "pamixer -t";
          "on-click-right" = "pavucontrol";
          "on-scroll-up" = "pamixer -i 5";
          "on-scroll-down" = "pamixer -d 5";
          "scroll-step" = 5;
          "format-icons" = {
            headphone = "";
            "hands-free" = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [ "" "" "" ];
          };
        };

        "pulseaudio#microphone" = {
          format = "{format_source}";
          "format-source" = "";
          "format-source-muted" = "󰍭";
          "on-click" = "pamixer --default-source -t";
          "on-click-right" = "pavucontrol";
          "on-scroll-up" = "pamixer --default-source -i 5";
          "on-scroll-down" = "pamixer --default-source -d 5";
          "scroll-step" = 5;
        };

        temperature = {
          "thermal-zone" = 1;
          format = " {temperatureC}°C";
          "critical-threshold" = 70;
          "format-critical" = " {temperatureF}°F";
          on-click = "ghostty --start-as=fullscreen --title btop sh -c 'btop'";
        };
      }
    ];
  };
}
