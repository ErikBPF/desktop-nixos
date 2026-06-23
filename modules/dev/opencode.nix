_: {
  flake.modules.home.opencode = {pkgs, ...}: {
    home.packages = [pkgs.opencode];
  };
}
