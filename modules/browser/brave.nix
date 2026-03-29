{...}: {
  flake.modules.home.brave = {
    pkgs,
    lib,
    ...
  }: let
    extensions = [
      "eimadpbcbfnmbkopoojfekhnkhdbieeh" # dark reader
      "ponfpcnoihfmfllpaingbgckeeldkhle" # Enhancer for YouTube
      "ghbmnnjooekpmoecnnnilnnbdlolhkhi" # Google Docs Offline
      "eiaeiblijfjekdanodkjadfinkhbfgcd" # Nord Pass
      "ioimlbgefgadofblnajllknopjboejda" # Transpose Pitch
      "nffaoalbilbmmfgbnbgppjihopabppdk" # Video Speed Controller
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock origin
    ];
    extJson = builtins.toJSON {external_update_url = "https://clients2.google.com/service/update2/crx";};
  in {
    programs.chromium = {
      enable = true;
      package = pkgs.brave;
      commandLineArgs = [
        "--disable-features=WebRtcAllowInputVolumeAdjustment,MediaRouter --enable-features=UseOzonePlatform --ozone-platform=wayland"
      ];
      inherit extensions;
    };

    # Brave looks for extensions in its own profile dir, not chromium's
    xdg.configFile = lib.listToAttrs (map (id: {
        name = "BraveSoftware/Brave-Browser/External Extensions/${id}.json";
        value.text = extJson;
      })
      extensions);
  };
}
