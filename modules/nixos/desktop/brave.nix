{...}: {
  programs.chromium = {
    enable = true;
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
}
