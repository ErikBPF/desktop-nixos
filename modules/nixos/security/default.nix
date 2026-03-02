{ ... }:
{
  imports = [
    ./aide.nix
    ./apparmor.nix
    ./audit.nix
    ./issue.nix
    ./login.nix
    ./pam.nix
    ./polkit.nix
    ./sudo.nix
  ];
}
