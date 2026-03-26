{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf (config.modules.graphics.enable && config.modules.graphics.driver == "intel") {
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
        libva-vdpau-driver # VDPAU backend for VA-API
        intel-ocl
        intel-vaapi-driver
      ];
    };
    services.xserver.videoDrivers = ["intel"];
    environment.systemPackages = with pkgs; [
      egl-wayland
      nvtopPackages.intel
    ];
  };
}
