{
  config,
  inputs,
  ...
}: {
  flake.modules = {
    nixos.hyprland = {...}: {
      programs = {
        hyprland.enable = true;
        hyprlock.enable = true;
      };
    };

    home.hyprland = {
      config,
      pkgs,
      lib,
      osConfig ? {},
      ...
    }: let
      hexToRgba = hex: alpha: "rgba(${hex}${alpha})";
      palette = config.colorScheme.palette;
      inactiveBorder = hexToRgba palette.base09 "aa";
      activeBorder = hexToRgba palette.base0D "aa";
      hasNvidiaDrivers = builtins.elem "nvidia" osConfig.services.xserver.videoDrivers;
      nvidiaEnv = [
        "NVD_BACKEND,direct"
        "LIBVA_DRIVER_NAME,nvidia"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "__NV_PRIME_RENDER_OFFLOAD,1"
        "__VK_LAYER_NV_optimus,NVIDIA_only"
      ];
    in {
      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
        settings = {
          "$terminal" = lib.mkDefault "ghostty";
          "$fileManager" = lib.mkDefault "nautilus --new-window";
          "$browser" = lib.mkDefault "brave";
          "$music" = lib.mkDefault "spotify";
          "$webapp" = lib.mkDefault "$browser --app";

          monitor = [
            ",preferred,auto,1"
          ];

          env =
            (lib.optionals hasNvidiaDrivers nvidiaEnv)
            ++ [
              "GDK_SCALE,1"
              "XCURSOR_SIZE,24"
              "HYPRCURSOR_SIZE,24"
              "XCURSOR_THEME,Vimix-cursors"
              "HYPRCURSOR_THEME,Vimix-cursors"
              "GDK_BACKEND,wayland"
              "QT_QPA_PLATFORM,wayland"
              "QT_QPA_PLATFORMTHEME,qt6ct"
              "QT_STYLE_OVERRIDE,kvantum"
              "SDL_VIDEODRIVER,wayland"
              "MOZ_ENABLE_WAYLAND,1"
              "ELECTRON_OZONE_PLATFORM_HINT,wayland"
              "OZONE_PLATFORM,wayland"
              "NIXOS_OZONE_WL,1"
              "CHROMIUM_FLAGS,\"--enable-features=UseOzonePlatform --enable-features=WebRTCPipeWireCapturer --ozone-platform=wayland  --gtk-version=4\""
              "XDG_DATA_DIRS,$XDG_DATA_DIRS:$HOME/.nix-profile/share:/nix/var/nix/profiles/default/share"
              "XCOMPOSEFILE,~/.XCompose"
              "EDITOR,cursor"
              "BROWSER,brave"
              "FILEMANAGER,ghostty -e yazi"
              "GTK_THEME,Tokyonight-Dark"
              "ADW_DEBUG_COLOR_SCHEME,prefer-dark"
            ];

          xwayland.force_zero_scaling = true;
          ecosystem.no_update_news = true;

          input = lib.mkDefault {
            kb_layout = "qwerty-fr";
            kb_variant = "qwerty-fr";
            kb_options = "compose:caps";
            numlock_by_default = true;
            follow_mouse = 1;
            mouse_refocus = 1;
            float_switch_override_focus = 1;
            scroll_factor = 0.5;
            sensitivity = 0;
            touchpad.natural_scroll = false;
          };

          gestures = lib.mkDefault {};

          general = {
            gaps_in = 5;
            gaps_out = 10;
            border_size = 2;
            "col.active_border" = activeBorder;
            "col.inactive_border" = inactiveBorder;
            resize_on_border = false;
            allow_tearing = false;
            layout = "dwindle";
          };

          decoration = {
            rounding = 4;
            shadow = {
              enabled = false;
              range = 30;
              render_power = 3;
              ignore_window = true;
              color = "rgba(00000045)";
            };
            blur = {
              enabled = true;
              size = 5;
              passes = 2;
              vibrancy = 0.1696;
            };
          };

          animations = {
            enabled = true;
            bezier = [
              "easeOutQuint,0.23,1,0.32,1"
              "easeInOutCubic,0.65,0.05,0.36,1"
              "linear,0,0,1,1"
              "almostLinear,0.5,0.5,0.75,1.0"
              "quick,0.15,0,0.1,1"
            ];
            animation = [
              "global, 1, 10, default"
              "border, 1, 5.39, easeOutQuint"
              "windows, 1, 4.79, easeOutQuint"
              "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
              "windowsOut, 1, 1.49, linear, popin 87%"
              "fadeIn, 1, 1.73, almostLinear"
              "fadeOut, 1, 1.46, almostLinear"
              "fade, 1, 3.03, quick"
              "layers, 1, 3.81, easeOutQuint"
              "layersIn, 1, 4, easeOutQuint, fade"
              "layersOut, 1, 1.5, linear, fade"
              "fadeLayersIn, 1, 1.79, almostLinear"
              "fadeLayersOut, 1, 1.39, almostLinear"
              "workspaces, 0, 0, ease"
            ];
          };

          dwindle = {
            pseudotile = true;
            preserve_split = true;
            force_split = 2;
          };

          master.new_status = "master";

          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
          };

          exec-once = [
            "quickshell -p ~/.config/quickshell/qml/Shell.qml"
            "hyprsunset"
            "systemctl --user start hyprpolkitagent"
            "systemctl --user start xdg-desktop-portal-gtk"
            "wl-clip-persist --clipboard regular & clipse -listen"
            "blueman-applet"
            "nm-applet --indicator"
            "tailscale-systray --accept-routes"
            "syncthingtray --single-instance --wait"
            "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP GTK_THEME ADW_DEBUG_COLOR_SCHEME"
            "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP GTK_THEME ADW_DEBUG_COLOR_SCHEME"
            "sleep 10; noisetorch -i -t 30; wpctl status | sed -n '/Sources:/,/^$/ s/^[│ ]*\\([0-9]\\+\\)\\. \\+Focusrite Scarlett 2i2 Analog Stereo.*/\\1/p' ;wpctl status | grep -oP '\\d+(?=\\.\\s+NoiseTorch Microphone for Focusrite Scarlett 2i2\\b)' | head -1 | xargs -r wpctl set-default"
            "[workspace 11] ghostty -e btop"
            "[workspace 11] sleep 3; spotify"
            "[workspace 10] sleep 3; teams-for-linux"
            "[workspace 10] sleep 3; discord"
            "[workspace 10] sleep 3; whatsapp-electron"
            "[workspace 1] sleep 3; $browser --restore-last-session"
          ];

          bind = [
            "SUPER, B, exec, $browser"
            "SUPER, N, exec, $terminal -e nvim"
            "SUPER, T, exec, $terminal"
            "SUPER, E, exec, $fileManager"
            "SUPER, D, exec, pkill rofi || rofi -show drun"
            "SUPER, W, killactive,"
            "SUPER, Backspace, killactive,"
            "SUPER, V, togglefloating,"
            "SUPER, F, fullscreen,"
            "SUPER, M, fullscreen, 1"
            "SUPER SHIFT, F, pseudo,"
            "SUPER, J, togglesplit, # dwindle"
            "SUPER, P, pseudo, # dwindle"
            "CTRL SHIFT, L, exec, hyprlock"
            "CTRL SHIFT, J, togglesplit,"
            "SUPER SHIFT, S, exec, grim -g \"$(slurp)\" - | swappy -f -"
            "SUPER SHIFT, C, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy && wtype -M ctrl v -M ctrl"
            "SUPER, SPACE, exec, pamixer --default-source -t"
            "SUPER, ESCAPE, exec, hyprlock"
            "SUPER SHIFT, ESCAPE, exit,"
            "SUPER CTRL, ESCAPE, exec, reboot"
            "SUPER SHIFT CTRL, ESCAPE, exec, systemctl poweroff"
            "SUPER, C, exec, ~/.config/quickshell/scripts/qs_manager.sh toggle calendar"
            "SUPER, G, exec, ~/.config/quickshell/scripts/qs_manager.sh toggle music"
            "SUPER, O, exec, ~/.config/quickshell/scripts/qs_manager.sh toggle battery"
            "SUPER, I, exec, ~/.config/quickshell/scripts/qs_manager.sh toggle network"
            "SUPER, Y, exec, ~/.config/quickshell/scripts/qs_manager.sh toggle wallpaper"
            "SUPER, U, exec, ~/.config/quickshell/scripts/qs_manager.sh toggle monitors"
            "SUPER, left, movefocus, l"
            "SUPER, right, movefocus, r"
            "SUPER, up, movefocus, u"
            "SUPER, down, movefocus, d"
            "SUPER SHIFT, h, movewindow, l"
            "SUPER SHIFT, l, movewindow, r"
            "SUPER SHIFT, k, movewindow, u"
            "SUPER SHIFT, j, movewindow, d"
            "SUPER CTRL, h, resizeactive, -20 0"
            "SUPER CTRL, l, resizeactive, 20 0"
            "SUPER CTRL, k, resizeactive, 0 -20"
            "SUPER CTRL, j, resizeactive, 0 20"
            "SUPER, 1, workspace, 1"
            "SUPER, 2, workspace, 2"
            "SUPER, 3, workspace, 3"
            "SUPER, 4, workspace, 4"
            "SUPER, 5, workspace, 5"
            "SUPER, 6, workspace, 6"
            "SUPER, 7, workspace, 7"
            "SUPER, 8, workspace, 8"
            "SUPER, 9, workspace, 9"
            "SUPER, 0, workspace, 10"
            "SUPER, a, workspace, 10"
            "SUPER, z, workspace, 11"
            "SUPER, x, workspace, 12"
            "SUPER, comma, workspace, -1"
            "SUPER, period, workspace, +1"
            "SUPER SHIFT, 1, movetoworkspace, 1"
            "SUPER SHIFT, 2, movetoworkspace, 2"
            "SUPER SHIFT, 3, movetoworkspace, 3"
            "SUPER SHIFT, 4, movetoworkspace, 4"
            "SUPER SHIFT, 5, movetoworkspace, 5"
            "SUPER SHIFT, 6, movetoworkspace, 6"
            "SUPER SHIFT, 7, movetoworkspace, 7"
            "SUPER SHIFT, 8, movetoworkspace, 8"
            "SUPER SHIFT, 9, movetoworkspace, 9"
            "SUPER SHIFT, 0, movetoworkspace, 10"
            "SUPER SHIFT, a, movetoworkspace, 10"
            "SUPER SHIFT, z, movetoworkspace, 11"
            "SUPER SHIFT, x, movetoworkspace, 12"
            "SUPER SHIFT, left, swapwindow, l"
            "SUPER SHIFT, right, swapwindow, r"
            "SUPER SHIFT, up, swapwindow, u"
            "SUPER SHIFT, down, swapwindow, d"
            "SUPER, minus, resizeactive, -100 0"
            "SUPER, equal, resizeactive, 100 0"
            "SUPER SHIFT, minus, resizeactive, 0 -100"
            "SUPER SHIFT, equal, resizeactive, 0 100"
            "SUPER, mouse_down, workspace, e+1"
            "SUPER, mouse_up, workspace, e-1"
            ", PRINT, exec, hyprshot -m region"
            "SHIFT, PRINT, exec, hyprshot -m window"
            "CTRL, PRINT, exec, hyprshot -m output"
            "SUPER, PRINT, exec, hyprpicker -a"
            "CTRL SUPER, V, exec, ghostty --class clipse -e clipse"
          ];

          bindm = [
            "SUPER, mouse:272, movewindow"
            "SUPER, mouse:273, resizewindow"
          ];

          bindel = [
            ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
            ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
            ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
            ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
            ",XF86MonBrightnessUp, exec, brightnessctl -e4 -n2 set 5%+"
            ",XF86MonBrightnessDown, exec, brightnessctl -e4 -n2 set 5%-"
          ];

          bindl = [
            ", XF86AudioNext, exec, playerctl next"
            ", XF86AudioPause, exec, playerctl play-pause"
            ", XF86AudioPlay, exec, playerctl play-pause"
            ", XF86AudioPrev, exec, playerctl previous"
          ];

          windowrule = [
            "suppress_event maximize, match:class .*"
            "tile on, match:class ^(chromium)$"
            "float on, match:class ^(org.pulseaudio.pavucontrol|blueberry.py)$"
            "float on, match:class ^(steam)$"
            "fullscreen on, match:class ^(com.libretro.RetroArch)$"
            "float on, match:class clipse"
            "size 622 652, match:class clipse"
            "stay_focused on, match:class clipse"
            "opacity 0.97 0.90, match:class .*"
            "opacity 0.90 0.80 override,match:class ^(com.mitchellh.ghostty)$"
            "opacity 1 1,match:class ^(brave-browser|chromium|google-chrome|google-chrome-unstable)$"
            "float on,match:class ^(teams-for-linux)$"
            "float on,match:class ^(discord)$"
            "float on,match:class ^(whatsapp-electron)$"
            "move 12 646,match:class ^(whatsapp-electron)$"
            "size 1056 643,match:class ^(whatsapp-electron)$"
            "move 12 47,match:class ^(teams-for-linux)$"
            "size 1056 585,match:class ^(teams-for-linux)$"
            "move 12 1304,match:class ^(discord)$"
            "size 1056 603,match:class ^(discord)$"
            "workspace 1, match:class ^(brave)$"
            "workspace 10, match:class ^(whatsapp-electron)$"
            "workspace 11, match:title ^(btop ~)$"
            "workspace 12, match:class ^(spotify)$"
            "workspace 10, match:class ^(teams-for-linux)$"
            "workspace 10, match:class ^(discord)$"
            "workspace 10, match:class ^(whatsapp-electron)$"
            "workspace 11 silent,match:title ^(btop ~)$"
            "workspace 11 silent,match:title ^(Lens)$"
            "workspace 10 silent,match:class ^(teams-for-linux)$"
            "workspace 10 silent,match:class ^(discord)$"
            "workspace 10 silent,match:class ^(whatsapp-electron)$"
          ];
        };

        extraConfig = ''
          cursor {
            no_hardware_cursors = true
          }
        '';
      };
      services.hyprpolkitagent.enable = true;
    };
  };
}
