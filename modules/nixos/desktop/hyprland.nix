inputs: {
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.desktop.enable {
    programs = {
      hyprland = {
        enable = true;
        # package = inputs.hyprland.packages.${pkgs.system}.hyprland;
        # package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        # portalPackage = pkgs.xdg-desktop-portal-hyprland; # Use stable nixpkgs version to fix Qt version mismatch
      };
      hyprlock.enable = true;
    };
  };
}
