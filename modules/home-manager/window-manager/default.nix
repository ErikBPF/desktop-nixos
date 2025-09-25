{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./hyprland.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./hypridle.nix
    ./mako.nix
    ./waybar.nix
    ./wofi.nix
    ./wlogout.nix
  ];
}
