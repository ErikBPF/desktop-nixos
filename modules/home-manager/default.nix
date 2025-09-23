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
    ./shell
    ./dev
    ./browser
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
  gtk3 = {
    extraConfig = {
      gtk-application-prefer-dark-theme=true;
      gtk-theme-name="Tokyonight-Dark-B";
      gtk-icon-theme-name="Papirus-Dark";
      gtk-cursor-theme-name="Vimix-cursors";
      gtk-cursor-theme-size=24;
    };
  };
    gtk4 = {
    extraConfig = {
      gtk-application-prefer-dark-theme=true;
      gtk-theme-name="Tokyonight-Dark-B";
      gtk-icon-theme-name="Papirus-Dark";
      gtk-cursor-theme-name="Vimix-cursors";
      gtk-cursor-theme-size=24;
    };
  };
  };
}