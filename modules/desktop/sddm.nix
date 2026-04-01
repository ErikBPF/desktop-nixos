{config, ...}: let
  cfgPath = config.configPath;
in {
  flake.modules.nixos.sddm = {pkgs, ...}: let
    wallpaper = cfgPath + "/themes/wallpapers/wallpaper.png";
    sddm-astronaut = pkgs.sddm-astronaut.override {
      embeddedTheme = "astronaut";
      themeConfig = {
        # Relative to the theme root — we copy the wallpaper into Backgrounds/ below.
        Background = "Backgrounds/wallpaper.png";
      };
    };
    # Extend the derivation to include the wallpaper in Backgrounds/
    # mkdir -p ensures the directory exists before cp — the base theme doesn't
    # create Backgrounds/ during installPhase, so the cp would fail without it.
    sddm-astronaut-with-wallpaper = sddm-astronaut.overrideAttrs (_old: {
      preFixup = ''
        mkdir -p $out/share/sddm/themes/sddm-astronaut-theme/Backgrounds
        cp ${wallpaper} $out/share/sddm/themes/sddm-astronaut-theme/Backgrounds/wallpaper.png
      '';
    });
  in {
    environment.systemPackages = [sddm-astronaut-with-wallpaper];
    services = {
      xserver.enable = true;
      displayManager = {
        sddm = {
          wayland.enable = true;
          enable = true;
          package = pkgs.kdePackages.sddm;
          enableHidpi = true;
          theme = "sddm-astronaut-theme";
          extraPackages = [sddm-astronaut-with-wallpaper];
        };
        autoLogin = {
          enable = false;
          user = "erik";
        };
      };
    };
  };
}
