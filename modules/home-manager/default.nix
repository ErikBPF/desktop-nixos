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
    theme = {
      name = "Tokyonight-Dark-B";
      # package = pkgs.gnome-themes-extra;
    };
    iconTheme = "Papirus-Dark";
    cursorTheme = "Bibata-Modern-Ice";
  gtk3 = {
    enable = true;
    extraConfig = {
      gtk-application-prefer-dark-theme=true;
      gtk-theme-name="Tokyonight-Dark-B";
      gtk-icon-theme-name="Papirus-Dark";
      gtk-cursor-theme-name="Bibata-Modern-Ice";
      gtk-cursor-theme-size=24;
    };
  };
    gtk4 = {
    enable = true;
    extraConfig = {
      gtk-application-prefer-dark-theme=true;
      gtk-theme-name="Tokyonight-Dark-B";
      gtk-icon-theme-name="Papirus-Dark";
      gtk-cursor-theme-name="Bibata-Modern-Ice";
      gtk-cursor-theme-size=24;
    };
  };
  };
}