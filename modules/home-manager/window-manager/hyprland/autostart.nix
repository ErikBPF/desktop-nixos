{
  config,
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "waybar"
      "hyprsunset"
      "systemctl --user start hyprpolkitagent"
      "wl-clip-persist --clipboard regular & clipse -listen"
      "blueman-applet" # Systray app for BT
      "nm-applet --indicator" # Systray app for Network/Wifi
      "tailscale-systray --accept-routes" # Systray tailscale
      "syncthingtray --single-instance"

      # "dropbox-cli start"  # Uncomment to run Dropbox
    ];

    exec = [
      # "pkill -SIGUSR2 waybar || waybar"
    ];
  };
}
