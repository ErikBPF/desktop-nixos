inputs: {
  config,
  pkgs,
  ...
}: let
  packages = import ../packages.nix {inherit pkgs;};
in {
  imports = [
    (import ./hyprland.nix inputs)
    (import ./system.nix)
    (import ./virtualization.nix)
  ];
}
