{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.lynis ];

  environment.etc."lynis/custom.prf".text = ''
    # NixOS handles its own firewall dynamically (nftables), skip legacy daemon tests
    skip-test=FIRE-4590

    # NixOS generates GRUB configuration on the fly and doesn't rely on traditional FHS boot configuration
    skip-test=BOOT-5122

    # NixOS doesn't use traditional package managers (apt, rpm, etc) and checks audit differently
    skip-test=PKGS-7398

    # Automation tooling is inherent to NixOS (nixos-rebuild, flakes) but Lynis looks for Puppet/Chef/Ansible
    skip-test=TOOL-5002

    # File permissions checking (often flags dynamically generated or read-only /nix/store symlinks)
    skip-test=FILE-7524

    # System configuration files (e.g. GRUB, pam, etc) in NixOS are read-only symlinks
    skip-test=AUTH-9229
    skip-test=AUTH-9230
  '';

}
