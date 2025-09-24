{
  config,
  pkgs,
  lib,
  ...
}:
{
  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
    "kvm-intel"
  ];

 services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    open = false;
    modesetting.enable = true;
    powerManagement.enable = true;

    powerManagement.finegrained = true;

    dynamicBoost.enable = lib.mkForce true;


    nvidiaSettings = true;

    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # prime = {
  	# 	offload = {
  	# 		enable = true;
  	# 		enableOffloadCmd = true;
  	# 	};

  	# 	nvidiaBusId = "PCI:01:00:0";
  	# 	intelBusId = "PCI:00:02:0";
  	# };
  };
  specialisation = {
    nvidia-sync.configuration = {
      system.nixos.tags = [ "nvidia-sync" ];
      hardware.nvidia = {
        powerManagement.finegrained = lib.mkForce false;

        prime.offload.enable = lib.mkForce false;
        prime.offload.enableOffloadCmd = lib.mkForce false;

        prime.sync.enable = lib.mkForce true;
      };
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

  #services.xserver.displayManager.wayland.enable = true;
}
