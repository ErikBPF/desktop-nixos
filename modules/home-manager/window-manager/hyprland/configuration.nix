{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./autostart.nix
    ./bindings.nix
    ./envs.nix
    ./input.nix
    ./looknfeel.nix
    ./windows.nix
  ];
  wayland.windowManager.hyprland = {
    settings = {
      # Default applications
      "$terminal" = lib.mkDefault "ghostty";
      "$fileManager" = lib.mkDefault "nautilus --new-window";
      "$browser" = lib.mkDefault "brave --enable-features=UseOzonePlatform  --ozone-platform=wayland  --enable-features=WebRTCPipeWireCapturer";
      "$music" = lib.mkDefault "spotify";
      "$webapp" = lib.mkDefault "$browser --app";

      monitor = [
        # Easily plug in any monitor
        ",preferred,auto,1"

        # 1080p-HDR monitor on the left, 4K-HDR monitor in the middle and 1080p vertical monitor on the right.
        "eDP-1,preferred,1592x1680,1.25"
        # monitor=HDMI-1,preferred,auto,1,mirror,eDP-1
        "desc:Samsung Electric Company QBQ90 0x01000E00,2560x1440,1080x240,1" #,bitdepth,10
        "desc:Samsung Electric Company C27F390 HX5MB00876,1920x1080,0x0,1,transform,1"
        "desc:Samsung Electric Company C27F390 HX5MB00881,1920x1080,3640x0,1,transform,3"
      ];
    };

    extraConfig = ''
      cursor {
        no_hardware_cursors = true
      }
      # Binds workspaces to my monitors only (find desc with: hyprctl monitors)
      workspace = 1, monitor:desc:Samsung Electric Company QBQ90 0x01000E00, default:true
      workspace = 2, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 3, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 4, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 5, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 6, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 7, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 8, monitor:desc:Samsung Electric Company QBQ90 0x01000E00
      workspace = 9, monitor:desc:Samsung Electric Company QBQ90 0x01000E00

      workspace = 10, monitor:desc:Samsung Electric Company C27F390 HX5MB00876
      workspace = 11, monitor:desc:Samsung Electric Company C27F390 HX5MB00881
      workspace = 12, monitor:eDP-1
    '';
  };
}
