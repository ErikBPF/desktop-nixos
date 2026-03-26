{...}: {
  flake.modules.home.brave = {pkgs, ...}: {
    programs.chromium = {
      enable = true;
      package = pkgs.brave;
      commandLineArgs = [
        "--disable-features=WebRtcAllowInputVolumeAdjustment,MediaRouter --enable-features=UseOzonePlatform --ozone-platform=wayland"
      ];
      extensions = [
        "eimadpbcbfnmbkopoojfekhnkhdbieeh" # dark reader
        "ponfpcnoihfmfllpaingbgckeeldkhle" # Enhancer for YouTube
        "ghbmnnjooekpmoecnnnilnnbdlolhkhi" # Google Docs Offline
        "eiaeiblijfjekdanodkjadfinkhbfgcd" # Nord Pass
        "ioimlbgefgadofblnajllknopjboejda" # Transpose Pitch
        "nffaoalbilbmmfgbnbgppjihopabppdk" # Video Speed Controller
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock origin
      ];
    };
  };
}
