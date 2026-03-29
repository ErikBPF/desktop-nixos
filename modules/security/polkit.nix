_: {
  flake.modules.nixos.polkit = _: {
    security.polkit.enable = true;
  };
}
