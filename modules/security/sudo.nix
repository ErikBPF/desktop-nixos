_: {
  flake.modules.nixos.sudo = _: {
    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
      extraConfig = ''
        Defaults timestamp_timeout=60
        Defaults timestamp_type=global
      '';
    };
  };
}
