_: {
  flake.modules.home.syncthing-tray = _: {
    services.syncthing = {
      enable = true;
      tray = {
        enable = true;
      };
    };
  };
}
