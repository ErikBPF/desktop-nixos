{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./hyprland.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./mako.nix
    ./quickshell
    ./rofi.nix
    ./mime.nix
  ];
}
