_: {
  flake.modules.nixos.orion-sunshine = {pkgs, ...}: {
    # --- Sunshine game streaming ---
    services.sunshine.enable = true;
    services.sunshine.capSysAdmin = true; # Required for KMS/DRM capture under gamescope/Wayland
    services.sunshine.openFirewall = true; # TCP 47984/47989/47990/48010, UDP 47998-48010

    # --- Xbox One/Series Bluetooth controller DKMS driver ---
    hardware.xpadneo.enable = true;

    # --- Extra controller udev rules (PS4/PS5, Switch Pro, 8BitDo) ---
    # steam-devices-udev-rules already active via jovian.steam.enable
    services.udev.packages = [pkgs.game-devices-udev-rules];

    # --- CPU/GPU performance mode daemon ---
    programs.gamemode.enable = true;
  };
}
