{...}: {
  flake.modules.nixos.headless = {...}: {
    # Disable all GUI components
    services.xserver.enable = false;
    hardware.bluetooth.enable = false;

    # Console defaults for headless operation
    console = {
      earlySetup = true;
      font = "Lat2-Terminus16";
      keyMap = "us";
    };

    # Disable documentation to save space
    documentation = {
      enable = false;
      man.enable = false;
      nixos.enable = false;
    };
  };
}
