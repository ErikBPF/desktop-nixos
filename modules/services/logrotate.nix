{...}: {
  flake.modules.nixos.logrotate = {...}: {
    services.logrotate.enable = true;

    services.journald.extraConfig = ''
      SystemMaxUse=50M
      SystemMaxFileSize=10M
    '';
  };
}
