_: {
  flake.modules.nixos.sudo = _: {
    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };
}
