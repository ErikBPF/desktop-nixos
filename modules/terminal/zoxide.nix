_: {
  flake.modules.home.zoxide = _: {
    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
