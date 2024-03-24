{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./wm/default.nix
    ./user/user.nix
  ];
}