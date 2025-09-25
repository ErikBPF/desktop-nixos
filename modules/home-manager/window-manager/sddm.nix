{
  config,
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    (pkgs.catppuccin-sddm.override {
      flavor = "mocha"; # Other flavors: latte, frappe, macchiato
      accent = "mauve"; # Other accents: blue, flamingo, green, etc.
      font = "Noto Sans";
      fontSize = "9";
      background = "/home/erik/Pictures/Wallpapers/wallpaper.png"; # Path to your custom wallpaper
      loginBackground = true; # Use the custom background for the login panel
    })
  ];
}
