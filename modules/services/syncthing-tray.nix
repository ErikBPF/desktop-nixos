_: {
  flake.modules.home.syncthing-tray = _: {
    services.syncthing = {
      # Don't enable the Home Manager syncthing service — NixOS manages it via services.syncthing.
      # Only enable the tray icon here.
      enable = false;
      tray = {
        enable = true;
      };
    };
  };
}
