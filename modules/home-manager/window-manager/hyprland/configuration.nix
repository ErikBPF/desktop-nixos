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
  wayland.windowManager.hyprland.settings = {
    # Default applications
    "$terminal" = lib.mkDefault "ghostty";
    "$fileManager" = lib.mkDefault "nautilus --new-window";
    "$browser" = lib.mkDefault "brave --enable-features=UseOzonePlatform  --ozone-platform=wayland  --enable-features=WebRTCPipeWireCapturer";
    "$music" = lib.mkDefault "spotify";
    "$webapp" = lib.mkDefault "$browser --app";

    monitor = [];
  };
}
