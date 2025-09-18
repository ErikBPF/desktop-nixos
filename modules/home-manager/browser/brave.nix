{lib, pkgs, ... }:

{
  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    extensions = [
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # dark reader
      { id = "ponfpcnoihfmfllpaingbgckeeldkhle"; } # Enhancer for YouTube
      { id = "ghbmnnjooekpmoecnnnilnnbdlolhkhi"; } # Google Docs Offline
      { id = "eiaeiblijfjekdanodkjadfinkhbfgcd"; } # Nord Pass
      { id = "ioimlbgefgadofblnajllknopjboejda"; } # Transpose Pitch
      { id = "nffaoalbilbmmfgbnbgppjihopabppdk"; } # Video Speed Controller
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # ublock origin
    ];
    commandLineArgs = [
      "--disable-features=WebRtcAllowInputVolumeAdjustment"
    ];
  }
}