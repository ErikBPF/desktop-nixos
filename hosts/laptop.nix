{ config, lib, pkgs, modulesPath, ... }:

let secrets = builtins.fromTOML (builtins.readFile "/tmp/secrets.toml"); in
{
users.users.erik.password = "test";
imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" "ahci"];
  boot.initrd.kernelModules = [ ];
   boot.kernelModules = ["kvm-intel"];
  boot.kernelParams = [];
  boot.extraModulePackages = [ ];


  swapDevices = [ ];

  services.logind = {
    lidSwitch = "ignore";
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
