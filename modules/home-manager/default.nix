inputs: {
  config,
  pkgs,
  lib,
  ...
}: let
  packages = import ../packages.nix {inherit pkgs lib;};

  themes = import ../themes.nix;
  
in {
  imports = [
    # (import ./window-manager/default.nix inputs)
    import ./terminal/default.nix
  ];


  # home.packages = packages.homePackages;

  # colorScheme = inputs.nix-colors.colorSchemes.tokyo-night-dark;

  # gtk = {
  #   enable = true;
  #   theme = {
  #     name = "Adwaita:dark";
  #     package = pkgs.gnome-themes-extra;
  #   };
  # };
}
