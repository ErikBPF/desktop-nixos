{...}: {
  flake.modules.nixos.sudo = {...}: {
    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };
}
