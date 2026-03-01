{...}: {
  imports = [
    ./apparmor.nix
    ./audit.nix
    ./pam.nix
    ./polkit.nix
    ./sudo.nix
  ];
}
