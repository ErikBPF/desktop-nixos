{ ... }:
{
  imports = [
    ./apparmor.nix
    ./audit.nix
    ./issue.nix
    ./login.nix
    ./lynis.nix
    ./pam.nix
    ./polkit.nix
    ./sudo.nix
    ./tor-monitor.nix
  ];
}
