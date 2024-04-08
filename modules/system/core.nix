{ config, lib, pkgs, ... }:

let secrets = builtins.fromTOML (builtins.readFile "/tmp/secrets.toml"); in
{
  imports = [
    ./boot.nix
    ./pkgs.nix
    ./user.nix
    ./init.nix
  ];

  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
  };
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  networking = {
    networkmanager.enable = true;
    networkmanager.wifi.backend = "iwd";
    firewall.enable = true;
    dhcpcd.enable = false;
  };
  services.nextdns = {
    enable = true;
    arguments = [ "-profile" secrets.misc.nextdns ];
  };

  users.mutableUsers = false;
  users.users.root.hashedPassword = "!";
  environment.binsh = "${pkgs.dash}/bin/dash";
  system.stateVersion = "unstable";
}
