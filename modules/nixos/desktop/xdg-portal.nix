{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.desktop.enable {
    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;
      # Hyprland module provides its own portal; include only GTK here to avoid duplicate units
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config = {
        common = {
          # Put GTK first to ensure OpenURI and other GTK interfaces are available
          default = ["gtk" "hyprland"];
          # Explicitly assign interfaces to their backends
          "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
          "org.freedesktop.impl.portal.OpenURI" = ["gtk"];
          "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
          "org.freedesktop.impl.portal.Screenshot" = ["hyprland"];
        };
      };
    };

    # Make Qt apps follow GTK settings for closer match to GTK theme
    qt = {
      enable = true;
      platformTheme = "gtk2";
      style = "adwaita-dark";
    };
  };
}
