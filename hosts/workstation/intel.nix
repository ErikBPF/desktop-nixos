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
  services.xserver.videoDrivers = ["intel"];
  environment.systemPackages = with pkgs; [
    egl-wayland
    libvdpau-va-gl
    intel-media-driver # Intel Media Driver for VAAPI
    vaapiIntel # Intel VA-API driver
    vaapiVdpau # VDPAU backend for VA-API
    libvdpau-va-gl # VDPAU driver with VA-API backend
    nvtopPackages.intel
  ];
}
