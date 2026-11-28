_: {
  # Brave reads external extensions from its own profile dir. Brave itself is
  # installed by modules/packages/desktop.nix.
  flake.modules.home.brave = {lib, ...}: let
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
    xdg.configFile = lib.listToAttrs (map (id: {
        name = "BraveSoftware/Brave-Browser/External Extensions/${id}.json";
        value.text = extJson;
      })
      extensions);
  };
}
