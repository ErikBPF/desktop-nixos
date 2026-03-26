{
  lib,
  pkgs,
  ...
}: {
  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    commandLineArgs = [
      "--disable-features=WebRtcAllowInputVolumeAdjustment,MediaRouter --enable-features=UseOzonePlatform --ozone-platform=wayland"
    ];
  };
}
