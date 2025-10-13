{
  pkgs,
  lib,
  ...
}: let
  packages = import ../packages.nix {inherit pkgs lib;};
in {
  # Install system packages
  environment.systemPackages = packages.systemPackages;

  # System-wide programs
  programs = {
    direnv.enable = true;
  };
}
