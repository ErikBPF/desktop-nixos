{
  config,
  pkgs,
  lib,
  ...
}: {
  boot = {
    kernelModules = [
      "kvm-intel"
    ];
  };
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [ 
      intel-media-driver
      libvdpau-va-gl
      vaapiIntel
      vaapiVdpau # VDPAU backend for VA-API
      intel-ocl 
      intel-vaapi-driver
       ];
  };
  services.xserver.videoDrivers = ["intel"];
  environment.systemPackages = with pkgs; [
    egl-wayland
    nvtopPackages.intel
  ];
}
