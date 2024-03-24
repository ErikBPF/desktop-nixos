{ pkgs, libs, inputs, ... }:

{
    programs.hyprland.enable = true;
    programs.hyprland.package = inputs.hyprland.packages."${pkgs.system}".hyprland;
    environment.variables.NIXOS_OZONE_WL = "1";
}