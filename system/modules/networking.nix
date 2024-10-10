{ config, pkgs, ... }:

{
  networking = {
	hostName = "laptop";
	networkmanager.enable = true;
	enableIPv6 = false;
	firewall.enable = false;
  };
}
