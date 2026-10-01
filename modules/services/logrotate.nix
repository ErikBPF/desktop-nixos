_: {
  flake.modules.nixos.logrotate = _: {
    services.logrotate.enable = true;

    services.journald.settings.Journal = {
      SystemMaxUse = "50M";
      SystemMaxFileSize = "10M";
    };
  };
}
