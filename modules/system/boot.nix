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
    # initrd.luks.devices."cryptroot" = {
    #   allowDiscards = true;
    #   keyFileSize = 4096;
    #   bypassWorkqueues = true;
    # };
    plymouth.enable = false;
  };

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "noatime" "nodiratime" "mode=755" ];
  };

  fileSystems."/perm" = {
    neededForBoot = true;
    device = "/dev/disk/by-label/NIXOS";
    fsType = "f2fs";
    options = [ "noatime" "nodiratime" "atgc" "gc_merge" "discard" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
  };

  systemd.services = {
    NetworkManager-wait-online.enable = false;
    systemd-udev-settle.enable = false;
  };
  #systemd.targets.network-online.enable = false;
}
