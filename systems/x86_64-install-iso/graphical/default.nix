{lib, ...}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.wireless.enable = lib.mkForce false;
  hardware.networking.enable = true;

  roles = {
    desktop.addons.gnome.enable = true;
  };

  nix.enable = true;
  services = {
    openssh.enable = true;
  };

  system = {
    locale.enable = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "nixos";
  };

  users.users = {
    nixos.extraGroups = ["networkmanager"];

    # TODO: reuse existing openss config
    nixos.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
    ];
  };

  system.stateVersion = "23.11";
}
