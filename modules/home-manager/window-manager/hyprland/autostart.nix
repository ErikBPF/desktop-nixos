{
  config,
  pkgs,
  ...
}: {
  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "pkill -SIGUSR2 waybar || waybar"
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

      "[workspace 1] $browser  --restore-last-session"
      "[workspace 11] lens-desktop"
      "[workspace 11] ghostty -e btop"
      "[workspace 12] spotify"
      "[workspace 10] teams-for-linux"
      "[workspace 10] discord"
      "[workspace 10] whatsapp-electron"

      # "dropbox-cli start"  # Uncomment to run Dropbox
    ];

    exec = [
      # "pkill -SIGUSR2 waybar || waybar"
    ];
  };
}
