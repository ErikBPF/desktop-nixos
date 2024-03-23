{ config, lib, pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      timeout = 0;
    };
    kernelPackages = pkgs.linuxPackages_zen;
    kernelParams = [ "fastboot" ];
    consoleLogLevel = 3;
    initrd.verbose = false;
    initrd.systemd.enable = true;
    plymouth.enable = false;
  };


  systemd.services = {
    NetworkManager-wait-online.enable = false;
    systemd-udev-settle.enable = false;
  };
  #systemd.targets.network-online.enable = false;
}
