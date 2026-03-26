{...}: {
  security.pam.services = {
    # greetd.enableGnomeKeyring = true;
    # greetd.kwallet.enable = false;
    sddm.enableGnomeKeyring = true;
    sddm.kwallet.enable = false;
    sddm-greeter.enableGnomeKeyring = true;
    # gdm.enableGnomeKeyring = true;
    # gdm.kwallet.enable = false;
    # gdm-greeter.enableGnomeKeyring = true;
    # gdm-password.kwallet.enable = true;
    # gdm-password.enableGnomeKeyring = true;
    hyprlock = {};
    login.enableGnomeKeyring = true;
    login.kwallet.enable = true;

  };
}
