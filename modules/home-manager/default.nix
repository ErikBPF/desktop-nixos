{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  packages = import ../packages.nix {inherit pkgs lib;};
in {
  imports = [
    ./window-manager
    ./terminal
  ];


  home.packages = packages.homePackages;

  colorScheme = inputs.nix-colors.colorSchemes.tokyo-night-dark;

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita:dark";
      package = pkgs.gnome-themes-extra;
    };
  };
}
