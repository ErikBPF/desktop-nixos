{
  config,
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "quickshell -p ~/.config/quickshell/qml/Shell.qml"
      # swww managed by systemd user service (quickshell/default.nix)
      "hyprsunset"
      "systemctl --user start hyprpolkitagent"
      "systemctl --user start xdg-desktop-portal-gtk"
      "wl-clip-persist --clipboard regular & clipse -listen"
      "blueman-applet" # Systray app for BT
      "nm-applet --indicator" # Systray app for Network/Wifi
      "tailscale-systray --accept-routes" # Systray tailscale
      "syncthingtray --single-instance --wait"
      "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland"
      "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland"
      # "sleep 10; noisetorch -i alsa_output.usb-Focusrite_Scarlett_2i2_USB-00.analog-stereo.monitor -t 30"
      "sleep 10; noisetorch -i -t 30; wpctl status | sed -n '/Sources:/,/^$/ s/^[│ ]*\([0-9]\+\)\. \+Focusrite Scarlett 2i2 Analog Stereo.*/\1/p' ;wpctl status | grep -oP '\d+(?=\.\s+NoiseTorch Microphone for Focusrite Scarlett 2i2\b)' | head -1 | xargs -r wpctl set-default"
      # No longer needed — hyprpaper now uses absolute path

      # "[workspace 11] lens-desktop"
      "[workspace 11] ghostty -e btop"
      "[workspace 11] sleep 3; spotify"
      "[workspace 10] sleep 3; teams-for-linux"
      "[workspace 10] sleep 3; discord"
      "[workspace 10] sleep 3; whatsapp-electron"
      "[workspace 1] sleep 3; $browser --restore-last-session"

      # "dropbox-cli start"  # Uncomment to run Dropbox
    ];

    exec = [
      # "pkill -SIGUSR2 waybar || waybar"
    ];
  };
}
