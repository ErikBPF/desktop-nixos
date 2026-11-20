_: {
  flake.modules.home.bluetooth-prompts = _: {
    dconf.settings."org/blueman/general".notification-daemon = false;
    services.blueman-applet.enable = true;
    systemd.user.services.blueman-applet.Service = {
      Type = "dbus";
      BusName = "org.blueman.Applet";
      Restart = "on-failure";
      RestartSec = 3;
    };

    # The graphical-session service owns startup instead of XDG autostart.
    xdg.configFile."autostart/blueman.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Blueman Applet
      Hidden=true
    '';
  };
}
