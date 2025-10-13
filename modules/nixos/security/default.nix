{...}: {
  imports = [
    ./apparmor.nix
    ./pam.nix
    ./polkit.nix
    ./sudo.nix
  ];
}
