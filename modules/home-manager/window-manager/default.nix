inputs: {
  config,
  inputs,
  pkgs,
  ...
}:{
  imports = [
    (import ./hyprland.nix inputs)
    (import ./hyprlock.nix inputs)
    (import ./hyprpaper.nix)
    (import ./hypridle.nix)
    (import ./mako.nix)
    (import ./waybar.nix inputs)
    (import ./wofi.nix)
  ];
}
