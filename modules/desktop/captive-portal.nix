_: {
  flake.modules.home.captive-portal = {
    pkgs,
    lib,
    ...
  }: let
    python = pkgs.python3.withPackages (ps: [ps.pygobject3]);
  in {
    systemd.user.services.captive-portal = {
      Unit = {
        Description = "Open Wi-Fi captive login once per connection";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        # A separate profile prevents the normal browser from absorbing the HTTP-only flags.
        ExecStart = "${python}/bin/python ${./_captive_portal.py} ${pkgs.systemd}/bin/systemd-run --user --collect --quiet --property=Type=exec ${pkgs.brave}/bin/brave --user-data-dir=%t/captive-portal/browser --no-first-run --no-default-browser-check --disable-features=BraveHttpsByDefault,HttpsUpgrades --new-window http://nmcheck.gnome.org/check_network_status.txt";
        Environment = "GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [pkgs.networkmanager (lib.getLib pkgs.glib)]}";
        RuntimeDirectory = "captive-portal";
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
