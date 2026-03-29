_: {
  flake.modules.home.clipboard = _: {
    services.cliphist = {
      enable = true;
      allowImages = true;
    };
  };
}
