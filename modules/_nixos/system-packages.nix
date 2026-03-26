{
  pkgs,
  lib,
  ...
}: let
  packages = import ../_packages.nix {inherit pkgs lib;};
in {
  # Install system packages
  environment.systemPackages = packages.systemPackages;

  # System-wide programs
}
