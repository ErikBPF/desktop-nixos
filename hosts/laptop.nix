{ config, lib, pkgs, modulesPath, ... }:

{
users.users.erik.password = "test";
imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" "aesni_intel" "cryptd" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelParams = [ "amd_pstate=active" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/nvme0n1p2";
    keyFile = "/dev/sda";
  };
  swapDevices = [ ];

  services.logind = {
    lidSwitch = "suspend";
    powerKey = "poweroff";
    powerKeyLongPress = "reboot";
  };

  hardware.sensor.iio.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;
  services.fprintd.enable = true;                                                                     

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
