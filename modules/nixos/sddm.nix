{
  pkgs,
  lib,
  config,
  ...
}: let
  sddm-astronaut = pkgs.sddm-astronaut.override {
    embeddedTheme = "astronaut";
  };
in {
  environment.systemPackages = [
    sddm-astronaut
  ];

  services = {
    xserver.enable = true;

    displayManager = {
      sddm = {
        wayland.enable = true;
        enable = true;
        package = pkgs.kdePackages.sddm;
        enableHidpi = true;
        theme = "sddm-astronaut-theme";

        extraPackages = [sddm-astronaut];
      };
      autoLogin = {
        enable = false;
        user = "erik";
      };
    };
  };
}
