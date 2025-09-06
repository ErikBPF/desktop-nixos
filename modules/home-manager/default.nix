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

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita:dark";
      package = pkgs.gnome-themes-extra;
    };
  };
}
