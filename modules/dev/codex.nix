{inputs, ...}: {
  flake.modules.home.codex = _: {
    imports = [inputs.codex-flake.homeManagerModules.default];

    programs.codex-profile = {
      enable = true;
      package.enable = true;
      rtk.enable = true;
      style.enable = true;
    };
  };
}
