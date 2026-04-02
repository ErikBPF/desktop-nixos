_: {
  flake.modules.home.brave = {
    pkgs,
    lib,
    ...
  }: let
    extensions = [
      "eimadpbcbfnmbkopoojfekhnkhdbieeh" # Dark Reader
      "ponfpcnoihfmfllpaingbgckeeldkhle" # Enhancer for YouTube
      "eiaeiblijfjekdanodkjadfinkhbfgcd" # NordPass
      "nffaoalbilbmmfgbnbgppjihopabppdk" # Video Speed Controller
      "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
      "plpkmjcnhhnpkblimgenmdhghfgghdpp" # The Great-er Tab Discarder
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
