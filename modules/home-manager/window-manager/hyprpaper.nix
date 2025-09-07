{
  config,
  pkgs,
  ...
}: let
  selected_wallpaper_path = "~/Pictures/Wallpapers/wallpaper.png";
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
        "${selected_wallpaper_path}"
      ];
    };
  };
}
