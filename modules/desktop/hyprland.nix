{
  config,
  inputs,
  ...
}: {
  flake.modules = {
    nixos.hyprland = _: {
      programs = {
        hyprland.enable = true;
        hyprlock.enable = true;
        uwsm.enable = true;
      };
    };

    home.hyprland = {
      config,
      pkgs,
      lib,
      osConfig ? {},
      ...
    }: let
      inherit (lib.generators) mkLuaInline;
      hexToRgba = hex: alpha: "rgba(${hex}${alpha})";
      inherit (config.colorScheme) palette;
      inactiveBorder = hexToRgba palette.base09 "aa";
      activeBorder = hexToRgba palette.base0D "aa";
      hasNvidiaDrivers = builtins.elem "nvidia" osConfig.services.xserver.videoDrivers;

      nvidiaEnv = [
        {_args = ["NVD_BACKEND" "direct"];}
        {_args = ["LIBVA_DRIVER_NAME" "nvidia"];}
        {_args = ["__GLX_VENDOR_LIBRARY_NAME" "nvidia"];}
        {_args = ["__NV_PRIME_RENDER_OFFLOAD" "1"];}
        {_args = ["__VK_LAYER_NV_optimus" "NVIDIA_only"];}
      ];

      baseEnv = [
        {_args = ["GDK_SCALE" "1"];}
        {_args = ["XCURSOR_SIZE" "24"];}
        {_args = ["HYPRCURSOR_SIZE" "24"];}
        {_args = ["XCURSOR_THEME" "Vimix-cursors"];}
        {_args = ["HYPRCURSOR_THEME" "Vimix-cursors"];}
        {_args = ["GDK_BACKEND" "wayland"];}
        {_args = ["QT_QPA_PLATFORM" "wayland"];}
        {_args = ["QT_QPA_PLATFORMTHEME" "qt6ct"];}
        {_args = ["QT_STYLE_OVERRIDE" "kvantum"];}
        {_args = ["SDL_VIDEODRIVER" "wayland"];}
        {_args = ["MOZ_ENABLE_WAYLAND" "1"];}
        {_args = ["ELECTRON_OZONE_PLATFORM_HINT" "wayland"];}
        {_args = ["OZONE_PLATFORM" "wayland"];}
        {_args = ["NIXOS_OZONE_WL" "1"];}
        {_args = ["CHROMIUM_FLAGS" "--enable-features=UseOzonePlatform --enable-features=WebRTCPipeWireCapturer --ozone-platform=wayland  --gtk-version=4"];}
        {
          _args = [
            "XDG_DATA_DIRS"
            (mkLuaInline ''(os.getenv("XDG_DATA_DIRS") or "") .. ":" .. (os.getenv("HOME") or "") .. "/.nix-profile/share:/nix/var/nix/profiles/default/share"'')
          ];
        }
        {
          _args = [
            "XCOMPOSEFILE"
            (mkLuaInline ''(os.getenv("HOME") or "") .. "/.XCompose"'')
          ];
        }
        {_args = ["BROWSER" "brave"];}
        {_args = ["FILEMANAGER" "ghostty +new-window -e yazi"];}
        # Force dark across toolkits for apps that ignore gsettings/settings.ini:
        #   GTK_THEME → GTK2/3/4 apps (swappy, etc). Points at the EXISTING dark
        #   variant (the earlier white-out was GTK_THEME=Tokyonight-Dark, deleted).
        #   ADW_DEBUG_COLOR_SCHEME → libadwaita apps, portal-independent.
        {_args = ["GTK_THEME" "adw-gtk3-dark"];}
        {_args = ["ADW_DEBUG_COLOR_SCHEME" "prefer-dark"];}
      ];

      workspaceBinds = lib.concatMap (i: let
        n = i + 1;
        key =
          if n == 10
          then "0"
          else toString n;
      in [
        {_args = ["SUPER + ${key}" (mkLuaInline "hl.dsp.focus({ workspace = ${toString n} })")];}
        {_args = ["SUPER + SHIFT + ${key}" (mkLuaInline "hl.dsp.window.move({ workspace = ${toString n} })")];}
      ]) (lib.range 0 9);
    in {
      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
        configType = "lua";

        settings = {
          terminal = {_var = "ghostty +new-window";};
          fileManager = {_var = "ghostty +new-window -e yazi";};
          fileManagerGui = {_var = "nautilus";};
          browser = {_var = "brave";};
          teamsApp = {_var = "brave --user-data-dir=$HOME/.local/share/brave-webapps/teams --no-first-run --no-default-browser-check --app=https://teams.microsoft.com/v2/";};
          whatsappApp = {_var = "brave --user-data-dir=$HOME/.local/share/brave-webapps/whatsapp --no-first-run --no-default-browser-check --app=https://web.whatsapp.com/";};
          monitor = lib.mkDefault [
            {
              output = "";
              mode = "preferred";
              position = "auto";
              scale = 1;
            }
          ];

          workspace_rule = lib.mkDefault [
            {
              workspace = "1";
              monitor = "HDMI-A-1";
              default = true;
              persistent = true;
            }
          ];

          env = (lib.optionals hasNvidiaDrivers nvidiaEnv) ++ baseEnv;

          config = {
            ecosystem.no_update_news = true;
            xwayland.force_zero_scaling = true;
            cursor.no_hardware_cursors = true;

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

            general = {
              gaps_in = 5;
              gaps_out = 10;
              border_size = 2;
              col = {
                active_border = activeBorder;
                inactive_border = inactiveBorder;
              };
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
                color = "rgba(00000045)";
              };
              blur = {
                enabled = true;
                size = 5;
                passes = 2;
                vibrancy = 0.1696;
              };
            };

            animations.enabled = true;

            dwindle = {
              preserve_split = true;
              force_split = 2;
            };

            master.new_status = "master";

            misc = {
              disable_hyprland_logo = true;
              disable_splash_rendering = true;
            };
          };

          curve = [
            {
              _args = [
                "easeOutQuint"
                {
                  type = "bezier";
                  points = [[0.23 1] [0.32 1]];
                }
              ];
            }
            {
              _args = [
                "easeInOutCubic"
                {
                  type = "bezier";
                  points = [[0.65 0.05] [0.36 1]];
                }
              ];
            }
            {
              _args = [
                "linear"
                {
                  type = "bezier";
                  points = [[0 0] [1 1]];
                }
              ];
            }
            {
              _args = [
                "almostLinear"
                {
                  type = "bezier";
                  points = [[0.5 0.5] [0.75 1.0]];
                }
              ];
            }
            {
              _args = [
                "quick"
                {
                  type = "bezier";
                  points = [[0.15 0] [0.1 1]];
                }
              ];
            }
          ];

          animation = [
            {
              leaf = "global";
              enabled = true;
              speed = 10;
              bezier = "default";
            }
            {
              leaf = "border";
              enabled = true;
              speed = 5.39;
              bezier = "easeOutQuint";
            }
            {
              leaf = "windows";
              enabled = true;
              speed = 4.79;
              bezier = "easeOutQuint";
            }
            {
              leaf = "windowsIn";
              enabled = true;
              speed = 4.1;
              bezier = "easeOutQuint";
              style = "popin 87%";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 1.49;
              bezier = "linear";
              style = "popin 87%";
            }
            {
              leaf = "fadeIn";
              enabled = true;
              speed = 1.73;
              bezier = "almostLinear";
            }
            {
              leaf = "fadeOut";
              enabled = true;
              speed = 1.46;
              bezier = "almostLinear";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 3.03;
              bezier = "quick";
            }
            {
              leaf = "layers";
              enabled = true;
              speed = 3.81;
              bezier = "easeOutQuint";
            }
            {
              leaf = "layersIn";
              enabled = true;
              speed = 4;
              bezier = "easeOutQuint";
              style = "fade";
            }
            {
              leaf = "layersOut";
              enabled = true;
              speed = 1.5;
              bezier = "linear";
              style = "fade";
            }
            {
              leaf = "fadeLayersIn";
              enabled = true;
              speed = 1.79;
              bezier = "almostLinear";
            }
            {
              leaf = "fadeLayersOut";
              enabled = true;
              speed = 1.39;
              bezier = "almostLinear";
            }
            {
              leaf = "workspaces";
              enabled = false;
              speed = 0;
              bezier = "ease";
            }
          ];

          on = [
            {
              _args = [
                "hyprland.start"
                (mkLuaInline ''
                  function()
                    hl.exec_cmd("systemctl --user restart quickshell")
                    hl.exec_cmd("hyprsunset")
                    hl.exec_cmd("systemctl --user start hyprpolkitagent")
                    hl.exec_cmd("systemctl --user start xdg-desktop-portal-gtk")
                    hl.exec_cmd("wl-clip-persist --clipboard regular & clipse -listen")
                    hl.exec_cmd("blueman-applet")
                    hl.exec_cmd("nm-applet --indicator")
                    hl.exec_cmd("tailscale-systray --accept-routes")
                    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP GTK_THEME ADW_DEBUG_COLOR_SCHEME")
                    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP GTK_THEME ADW_DEBUG_COLOR_SCHEME")
                    -- +new-window routes through the running (or D-Bus-activated)
                    -- ghostty instance instead of forking a fresh cold GTK4/GPU
                    -- process each time (~1.8s). Plain `ghostty -e cmd` does NOT
                    -- honour gtk-single-instance; the action does. Same for yazi.
                    hl.exec_cmd("ghostty +new-window -e btop",            { workspace = 11 })
                    hl.exec_cmd("sleep 3; obsidian",          { workspace = 11 })
                    hl.exec_cmd("sleep 3; ghostty --gtk-single-instance=false --class=com.pastelariadev.spotify_tui --title=spotify-tui -e spotify_player", { workspace = 12 })
                    hl.exec_cmd(teamsApp, { workspace = 10 })
                    hl.exec_cmd("sleep 3; discord", { workspace = 10 })
                    hl.exec_cmd("sleep 3; " .. whatsappApp, { workspace = 10 })
                    hl.exec_cmd("sleep 3; " .. browser .. " --restore-last-session", { workspace = 1 })
                  end
                '')
              ];
            }
          ];

          bind =
            [
              {_args = ["SUPER + B" (mkLuaInline "hl.dsp.exec_cmd(browser)")];}
              {_args = ["SUPER + N" (mkLuaInline ''hl.dsp.exec_cmd(terminal .. " -e nvim")'')];}
              {_args = ["SUPER + T" (mkLuaInline "hl.dsp.exec_cmd(terminal)")];}
              {_args = ["SUPER + E" (mkLuaInline "hl.dsp.exec_cmd(fileManager)")];}
              {_args = ["SUPER + SHIFT + E" (mkLuaInline "hl.dsp.exec_cmd(fileManagerGui)")];}
              {_args = ["SUPER + slash" (mkLuaInline ''hl.dsp.exec_cmd("yazi-help")'')];}
              {_args = ["SUPER + D" (mkLuaInline ''hl.dsp.exec_cmd("pkill rofi || rofi -show drun")'')];}
              {_args = ["SUPER + W" (mkLuaInline "hl.dsp.window.close()")];}
              {_args = ["SUPER + Backspace" (mkLuaInline "hl.dsp.window.close()")];}
              {_args = ["SUPER + V" (mkLuaInline ''hl.dsp.window.float({ action = "toggle" })'')];}
              {_args = ["SUPER + F" (mkLuaInline "hl.dsp.window.fullscreen()")];}
              {_args = ["SUPER + M" (mkLuaInline ''hl.dsp.window.fullscreen({ mode = "maximized" })'')];}
              {_args = ["SUPER + SHIFT + F" (mkLuaInline "hl.dsp.window.pseudo()")];}
              {_args = ["SUPER + J" (mkLuaInline ''hl.dsp.layout("togglesplit")'')];}
              {_args = ["SUPER + P" (mkLuaInline "hl.dsp.window.pseudo()")];}
              {_args = ["CTRL + SHIFT + L" (mkLuaInline ''hl.dsp.exec_cmd("hyprlock")'')];}
              {_args = ["CTRL + SHIFT + J" (mkLuaInline ''hl.dsp.layout("togglesplit")'')];}
              {_args = ["SUPER + SHIFT + S" (mkLuaInline ''hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f -]])'')];}
              {_args = ["SUPER + SHIFT + C" (mkLuaInline ''hl.dsp.exec_cmd("cliphist list | rofi -dmenu | cliphist decode | wl-copy && wtype -M ctrl v -M ctrl")'')];}
              {_args = ["SUPER + SPACE" (mkLuaInline ''hl.dsp.exec_cmd("pamixer --default-source -t")'')];}
              {_args = ["SUPER + ESCAPE" (mkLuaInline ''hl.dsp.exec_cmd("hyprlock")'')];}
              {_args = ["SUPER + SHIFT + ESCAPE" (mkLuaInline "hl.dsp.exit()")];}
              {_args = ["SUPER + CTRL + ESCAPE" (mkLuaInline ''hl.dsp.exec_cmd("reboot")'')];}
              {_args = ["SUPER + SHIFT + CTRL + ESCAPE" (mkLuaInline ''hl.dsp.exec_cmd("systemctl poweroff")'')];}
              {_args = ["SUPER + C" (mkLuaInline ''hl.dsp.exec_cmd("~/.config/quickshell/scripts/qs_manager.sh toggle calendar")'')];}
              {_args = ["SUPER + G" (mkLuaInline ''hl.dsp.exec_cmd("~/.config/quickshell/scripts/qs_manager.sh toggle music")'')];}
              {_args = ["SUPER + O" (mkLuaInline ''hl.dsp.exec_cmd("~/.config/quickshell/scripts/qs_manager.sh toggle battery")'')];}
              {_args = ["SUPER + I" (mkLuaInline ''hl.dsp.exec_cmd("~/.config/quickshell/scripts/qs_manager.sh toggle network")'')];}
              {_args = ["SUPER + Y" (mkLuaInline ''hl.dsp.exec_cmd("~/.config/quickshell/scripts/qs_manager.sh toggle wallpaper")'')];}
              {_args = ["SUPER + U" (mkLuaInline ''hl.dsp.exec_cmd("~/.config/quickshell/scripts/qs_manager.sh toggle monitors")'')];}
              {_args = ["SUPER + left" (mkLuaInline ''hl.dsp.focus({ direction = "l" })'')];}
              {_args = ["SUPER + right" (mkLuaInline ''hl.dsp.focus({ direction = "r" })'')];}
              {_args = ["SUPER + up" (mkLuaInline ''hl.dsp.focus({ direction = "u" })'')];}
              {_args = ["SUPER + down" (mkLuaInline ''hl.dsp.focus({ direction = "d" })'')];}
              {_args = ["SUPER + SHIFT + h" (mkLuaInline ''hl.dsp.window.move({ direction = "l" })'')];}
              {_args = ["SUPER + SHIFT + l" (mkLuaInline ''hl.dsp.window.move({ direction = "r" })'')];}
              {_args = ["SUPER + SHIFT + k" (mkLuaInline ''hl.dsp.window.move({ direction = "u" })'')];}
              {_args = ["SUPER + SHIFT + j" (mkLuaInline ''hl.dsp.window.move({ direction = "d" })'')];}
              {_args = ["SUPER + CTRL + h" (mkLuaInline "hl.dsp.window.resize({ x = -20, y = 0, relative = true })")];}
              {_args = ["SUPER + CTRL + l" (mkLuaInline "hl.dsp.window.resize({ x = 20, y = 0, relative = true })")];}
              {_args = ["SUPER + CTRL + k" (mkLuaInline "hl.dsp.window.resize({ x = 0, y = -20, relative = true })")];}
              {_args = ["SUPER + CTRL + j" (mkLuaInline "hl.dsp.window.resize({ x = 0, y = 20, relative = true })")];}
            ]
            ++ workspaceBinds
            ++ [
              {_args = ["SUPER + a" (mkLuaInline "hl.dsp.focus({ workspace = 10 })")];}
              {_args = ["SUPER + z" (mkLuaInline "hl.dsp.focus({ workspace = 11 })")];}
              {_args = ["SUPER + x" (mkLuaInline "hl.dsp.focus({ workspace = 12 })")];}
              {_args = ["SUPER + comma" (mkLuaInline ''hl.dsp.focus({ workspace = "-1" })'')];}
              {_args = ["SUPER + period" (mkLuaInline ''hl.dsp.focus({ workspace = "+1" })'')];}
              {_args = ["SUPER + SHIFT + a" (mkLuaInline "hl.dsp.window.move({ workspace = 10 })")];}
              {_args = ["SUPER + SHIFT + z" (mkLuaInline "hl.dsp.window.move({ workspace = 11 })")];}
              {_args = ["SUPER + SHIFT + x" (mkLuaInline "hl.dsp.window.move({ workspace = 12 })")];}
              {_args = ["SUPER + SHIFT + left" (mkLuaInline ''hl.dsp.window.swap({ direction = "l" })'')];}
              {_args = ["SUPER + SHIFT + right" (mkLuaInline ''hl.dsp.window.swap({ direction = "r" })'')];}
              {_args = ["SUPER + SHIFT + up" (mkLuaInline ''hl.dsp.window.swap({ direction = "u" })'')];}
              {_args = ["SUPER + SHIFT + down" (mkLuaInline ''hl.dsp.window.swap({ direction = "d" })'')];}
              {_args = ["SUPER + minus" (mkLuaInline "hl.dsp.window.resize({ x = -100, y = 0, relative = true })")];}
              {_args = ["SUPER + equal" (mkLuaInline "hl.dsp.window.resize({ x = 100, y = 0, relative = true })")];}
              {_args = ["SUPER + SHIFT + minus" (mkLuaInline "hl.dsp.window.resize({ x = 0, y = -100, relative = true })")];}
              {_args = ["SUPER + SHIFT + equal" (mkLuaInline "hl.dsp.window.resize({ x = 0, y = 100, relative = true })")];}
              {_args = ["SUPER + mouse_down" (mkLuaInline ''hl.dsp.focus({ workspace = "e+1" })'')];}
              {_args = ["SUPER + mouse_up" (mkLuaInline ''hl.dsp.focus({ workspace = "e-1" })'')];}
              {_args = ["PRINT" (mkLuaInline ''hl.dsp.exec_cmd("hyprshot -m region")'')];}
              {_args = ["SHIFT + PRINT" (mkLuaInline ''hl.dsp.exec_cmd("hyprshot -m window")'')];}
              {_args = ["CTRL + PRINT" (mkLuaInline ''hl.dsp.exec_cmd("hyprshot -m output")'')];}
              {_args = ["SUPER + PRINT" (mkLuaInline ''hl.dsp.exec_cmd("hyprpicker -a")'')];}
              {_args = ["CTRL + SUPER + V" (mkLuaInline ''hl.dsp.exec_cmd("ghostty --class clipse -e clipse")'')];}

              {_args = ["SUPER + mouse:272" (mkLuaInline "hl.dsp.window.drag()") {mouse = true;}];}
              {_args = ["SUPER + mouse:273" (mkLuaInline "hl.dsp.window.resize()") {mouse = true;}];}

              {
                _args = [
                  "XF86AudioRaiseVolume"
                  (mkLuaInline ''hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+")'')
                  {
                    locked = true;
                    repeating = true;
                  }
                ];
              }
              {
                _args = [
                  "XF86AudioLowerVolume"
                  (mkLuaInline ''hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")'')
                  {
                    locked = true;
                    repeating = true;
                  }
                ];
              }
              {
                _args = [
                  "XF86AudioMute"
                  (mkLuaInline ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")'')
                  {
                    locked = true;
                    repeating = true;
                  }
                ];
              }
              {
                _args = [
                  "XF86AudioMicMute"
                  (mkLuaInline ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")'')
                  {
                    locked = true;
                    repeating = true;
                  }
                ];
              }
              {
                _args = [
                  "XF86MonBrightnessUp"
                  (mkLuaInline ''hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+")'')
                  {
                    locked = true;
                    repeating = true;
                  }
                ];
              }
              {
                _args = [
                  "XF86MonBrightnessDown"
                  (mkLuaInline ''hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-")'')
                  {
                    locked = true;
                    repeating = true;
                  }
                ];
              }

              {_args = ["XF86AudioNext" (mkLuaInline ''hl.dsp.exec_cmd("playerctl next")'') {locked = true;}];}
              {_args = ["XF86AudioPause" (mkLuaInline ''hl.dsp.exec_cmd("playerctl play-pause")'') {locked = true;}];}
              {_args = ["XF86AudioPlay" (mkLuaInline ''hl.dsp.exec_cmd("playerctl play-pause")'') {locked = true;}];}
              {_args = ["XF86AudioPrev" (mkLuaInline ''hl.dsp.exec_cmd("playerctl previous")'') {locked = true;}];}
            ];

          window_rule = [
            {
              match.class = ".*";
              suppress_event = "maximize";
            }
            {
              match.class = "^(chromium)$";
              tile = true;
            }
            {
              match.class = "^(org.pulseaudio.pavucontrol|blueberry.py)$";
              float = true;
            }
            {
              match.class = "^(steam)$";
              float = true;
            }
            {
              match.class = "^(com.libretro.RetroArch)$";
              fullscreen = true;
            }
            {
              match.class = "clipse";
              float = true;
            }
            {
              match.class = "clipse";
              size = "622 652";
            }
            {
              match.class = "clipse";
              stay_focused = true;
            }
            {
              match.class = ".*";
              opacity = "0.97 0.90";
            }
            {
              match.class = "^(com.mitchellh.ghostty)$";
              opacity = "0.90 0.80 override";
            }
            {
              match.class = "^(brave-browser|chromium|google-chrome|google-chrome-unstable)$";
              opacity = "1 1";
            }
            {
              match.class = "^discord$";
              float = true;
            }
            {
              match.class = "^discord$";
              move = "12 1304";
            }
            {
              match.class = "^discord$";
              size = "1056 603";
            }
            {
              match.class = "^.*\\.spotify_tui$";
              float = true;
            }
            {
              match.class = "^.*\\.spotify_tui$";
              move = "12 47";
            }
            {
              match.class = "^.*\\.spotify_tui$";
              size = "1056 585";
            }
            {
              match.class = "^(brave-browser|chromium|google-chrome|google-chrome-unstable)$";
              workspace = "1";
            }
            {
              match.title = "^(btop ~)$";
              workspace = "11";
            }
            {
              match.class = "^(obsidian)$";
              workspace = "11";
            }
            {
              match.class = "^.*\\.spotify_tui$";
              workspace = "12";
            }
            {
              match.class = "^discord$";
              workspace = "10";
            }
            {
              match.title = "^(btop ~)$";
              workspace = "11 silent";
            }
            {
              match.title = "^(Lens)$";
              workspace = "11 silent";
            }
            {
              match.class = "^(obsidian)$";
              workspace = "11 silent";
            }
            {
              match.class = "^.*\\.spotify_tui$";
              workspace = "12 silent";
            }
            {
              match.class = "^discord$";
              workspace = "10 silent";
            }
            {
              match.class = "^brave-.*teams\\.microsoft\\.com.*$";
              float = true;
            }
            {
              match.class = "^brave-.*teams\\.microsoft\\.com.*$";
              workspace = "10 silent";
            }
            {
              match.class = "^brave-.*teams\\.microsoft\\.com.*$";
              size = "1056 585";
            }
            {
              match.class = "^brave-.*teams\\.microsoft\\.com.*$";
              move = "12 47";
            }
            {
              match.class = "^brave-.*web\\.whatsapp\\.com.*$";
              float = true;
            }
            {
              match.class = "^brave-.*web\\.whatsapp\\.com.*$";
              move = "12 646";
            }
            {
              match.class = "^brave-.*web\\.whatsapp\\.com.*$";
              size = "1056 643";
            }
            {
              match.class = "^brave-.*web\\.whatsapp\\.com.*$";
              workspace = "10";
            }
            {
              match.class = "^brave-.*web\\.whatsapp\\.com.*$";
              workspace = "10 silent";
            }
            {
              match.class = "^(teams-for-linux)$";
              float = true;
            }
            {
              match.class = "^(teams-for-linux)$";
              workspace = "10 silent";
            }
            {
              match.class = "^(teams-for-linux)$";
              size = "1056 585";
            }
            {
              match.class = "^(teams-for-linux)$";
              move = "12 47";
            }
            {
              match.title = "^(WhatsApp Electron.*)$";
              float = true;
            }
            {
              match.title = "^(WhatsApp Electron.*)$";
              move = "12 646";
            }
            {
              match.title = "^(WhatsApp Electron.*)$";
              size = "1056 643";
            }
            {
              match.title = "^(WhatsApp Electron.*)$";
              workspace = "10";
            }
            {
              match.title = "^(WhatsApp Electron.*)$";
              workspace = "10 silent";
            }
          ];
        };
      };
      services.hyprpolkitagent.enable = true;
      systemd.user.services.hyprpolkitagent.Install.WantedBy = lib.mkForce [];
    };
  };
}
