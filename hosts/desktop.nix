{ config, lib, pkgs, modulesPath, ... }:

let secrets = builtins.fromTOML (builtins.readFile "/tmp/secrets.toml"); in
{
  users.users.erik.password = secrets.passwd.desktop;
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "usbhid" "aesni_intel" "cryptd" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelParams = [ "amd_pstate=active" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/nvme0n1p2";
    keyFile = "/dev/sda";
  };
  swapDevices = [ ];

  services.logind = {
    powerKey = "poweroff";
    powerKeyLongPress = "reboot";
  };

  services.syncthing.settings.devices."Server" = { id = secrets.syncthing.server; };
  services.syncthing.settings.folders = {
    "Documents".devices = [ "Server" ];
    "Code".devices = [ "Server" ];
    "Camera".devices = [ "Server" ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
