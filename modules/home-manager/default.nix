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

  home.file = {
    ".config/keyboard" = {
      source = ../../config/keyboard;
      recursive = true;
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita:dark";
      package = pkgs.gnome-themes-extra;
    };
  };
}
