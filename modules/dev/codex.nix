_: {
  flake.modules.home.codex = {pkgs, ...}: {
    home.packages = [pkgs.codex];
  };
}
