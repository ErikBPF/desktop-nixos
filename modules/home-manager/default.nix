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


  services.xserver = {
    # ...

    xkb = {
      layout = "us";
      variant = "qwerty-fr";
      extraLayouts = {
        qwerty-fr = {
          description = "QWERTY with French symbols and diacritics";
          languages = ["eng"];
          symbolsFile = /home/erik/.config/keyboard/us_querty-fr;
        };
      };
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
