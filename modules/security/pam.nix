_: {
  flake.modules.nixos.pam = _: {
    security.pam.services = {
      sddm.enableGnomeKeyring = true;
      sddm.kwallet.enable = false;
      sddm-greeter.enableGnomeKeyring = true;
      hyprlock = {};
      login.enableGnomeKeyring = true;
      login.kwallet.enable = true;
    };
  };
}
