_: {
  flake.modules.nixos.logrotate = _: {
    services.logrotate.enable = true;

    services.journald.extraConfig = ''
      SystemMaxUse=50M
      SystemMaxFileSize=10M
    '';
  };
}
