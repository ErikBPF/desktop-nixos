{...}: {
  imports = [
    ./firewall.nix
    ./openssh.nix
    ./resolved.nix
    ./tailscale.nix
  ];
}
