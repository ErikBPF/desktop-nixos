{...}: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Enable experimental features (battery, LC3, etc.)
    settings = {
      General = {
        Experimental = true;
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };

  # Bluetooth manager (tray + UI)
  services.blueman.enable = true;
}
