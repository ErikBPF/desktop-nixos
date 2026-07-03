_: {
  # Auto-mount removable drives + a tray icon. Complements yazi's `M` mount
  # manager for the GUI/plug-and-go path.
  flake.modules.home.udiskie = _: {
    services.udiskie = {
      enable = true;
      automount = true;
      notify = true;
      tray = "auto";
    };
  };
}
