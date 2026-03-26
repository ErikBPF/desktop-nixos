{...}: {
  flake.modules.home.clipboard = {...}: {
    services.cliphist = {
      enable = true;
      allowImages = true;
    };
  };
}
