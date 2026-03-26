{...}: {
  flake.modules.home.zoxide = {...}: {
    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
