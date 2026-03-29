_: {
  flake.modules.nixos.resolved = _: {
    services.resolved = {
      enable = true;
      settings.Resolve.LLMNR = "no";
    };
  };
}
