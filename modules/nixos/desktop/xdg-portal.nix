{
  config,
  pkgs,
  ...
}: {
  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    # Hyprland module provides its own portal; include only GTK here to avoid duplicate units
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
    config = {
      common = {
        default = ["hyprland" "gtk"];
        "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
      };
    };
  };

  # Make Qt apps follow GNOME/GTK settings for closer match to GTK theme
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };
}
