{
  config,
  pkgs,
  ...
}: let
  selected_wallpaper_path = "/home/erik/Pictures/Wallpapers/wallpaper.png";
in {
  home.file = {
    "Pictures/Wallpapers" = {
      source = ../../../config/themes/wallpapers;
      recursive = true;
    };
  };
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [
        selected_wallpaper_path
      ];
      wallpaper = [
        ",${selected_wallpaper_path}"
      ];
      ipc = "on";
      splash = false;
    };
  };
}
