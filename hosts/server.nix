{ config, lib, pkgs, modulesPath, ... }:

let secrets = builtins.fromTOML (builtins.readFile "/tmp/secrets.toml"); in
{
users.users.erik.password = secrets.passwd.server;

  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" "aesni_intel" "cryptd" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelParams = [ ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/nvme0n1p2";
    keyFile = "/dev/mmcblk0";
  };
  swapDevices = [ ];

  services.logind = {
    lidSwitch = "ignore";
    powerKey = "poweroff";
    powerKeyLongPress = "reboot";
  };

  services.syncthing.settings.devices."Laptop" = { id = secrets.syncthing.laptop; };
  services.syncthing.settings.devices."Desktop" = { id = secrets.syncthing.desktop; };
  services.syncthing.settings.folders = {
    "Documents".devices = [ "Laptop" "Desktop" ];
    "Code".devices = [ "Laptop" "Desktop" ];
    "Camera".devices = [ "Laptop" "Desktop" ];
  };                                      
  services.syncthing.guiAddress = "0.0.0.0:8384";
  

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}

