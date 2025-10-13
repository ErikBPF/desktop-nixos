{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf (config.modules.graphics.enable && config.modules.graphics.driver == "nvidia") {
    boot = {
      kernelModules = [
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
        "kvm-intel"
      ];
      # kernelParams = ["module_blacklist=i915"];
      initrd.kernelModules = ["nvidia"];
      extraModulePackages = [config.boot.kernelPackages.nvidia_x11];
      blacklistedKernelModules = ["nouveau"];
    };

    services.xserver.videoDrivers = ["intel" "nvidia"];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        libvdpau-va-gl
        vaapiIntel
        nvidia-vaapi-driver
        vaapiVdpau # VDPAU backend for VA-API
        intel-ocl
        intel-vaapi-driver
      ];
    };

    hardware.nvidia = {
      open = false;
      modesetting.enable = true;
      powerManagement.enable = lib.mkForce true;

      powerManagement.finegrained = false;

      dynamicBoost.enable = lib.mkForce false;

      nvidiaSettings = true;
      nvidiaPersistenced = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;

      prime = {
        offload = {
          enable = false;
          enableOffloadCmd = false;
        };
        sync = {
          enable = true;
        };

        nvidiaBusId = "PCI:01:00:0";
        intelBusId = "PCI:00:02:0";
      };
    };

    environment.sessionVariables = {
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
      LIBVA_DRIVER_NAME = "nvidia";
      NVD_BACKEND = "direct"; # For hardware video acceleration
      ELECTRON_OZONE_PLATFORM_HINT = "auto"; # Electron app flickering fix
      NIXOS_OZONE_WL = "1"; # Auto configure Electron apps for Wayland
    };

    environment.systemPackages = with pkgs; [
      egl-wayland
      nvidia-vaapi-driver
      libvdpau-va-gl
      nvtopPackages.nvidia
      nvtopPackages.intel
    ];

    # services.xserver.displayManager.wayland.enable = true;
  };
}
