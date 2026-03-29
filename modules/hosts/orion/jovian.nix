_: {
  flake.modules.nixos.orion-jovian = {lib, ...}: {
    # --- Jovian Steam HTPC ---
    jovian.steam.enable = true;
    jovian.steam.autoStart = true;
    jovian.steam.user = "erik";
    jovian.steam.desktopSession = "hyprland";

    jovian.hardware.has.amd.gpu = true;

    # --- AMD GPU environment ---
    environment.variables.AMD_VULKAN_ICD = "RADV";

    # --- Silent boot ---
    boot.kernelParams = lib.mkAfter [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    boot.consoleLogLevel = 0;
  };
}
