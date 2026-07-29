{inputs, ...}: {
  flake.modules.home.buzz = {
    imports = [inputs.buzz-flake.homeManagerModules.withPackage];
    programs.buzz.enable = true;
  };
}
