_: {
  flake.modules.home.claude-code = {pkgs, ...}: {
    home.packages = [pkgs.claude-code];
  };
}
