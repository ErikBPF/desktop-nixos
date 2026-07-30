{inputs, ...}: {
  flake.modules.home.buzz = {
    imports = [inputs.buzz-flake.homeManagerModules.withPackage];
    programs.buzz.enable = true;
    home.sessionVariables.BUZZ_RELAY_URL = "http://kepler.netbird.internal:3000";
  };
}
