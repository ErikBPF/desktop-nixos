{...}: {
  flake.modules.nixos.avahi = {...}: {
    services.avahi = {
      enable = false;
    };
  };
}
