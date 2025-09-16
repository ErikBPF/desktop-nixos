{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [./hyprland/configuration.nix];
  wayland.windowManager.hyprland = {
    enable = true;
    # package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = true;
  };
  services.hyprpolkitagent.enable = true;
}
