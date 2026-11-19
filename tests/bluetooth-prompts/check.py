"""Check evaluated Endeavour Bluetooth prompt and session configuration."""
import json
import subprocess

projection = '''c: let h = c.home-manager.users.erik; in {
  dialogs = h.dconf.settings."org/blueman/general"."notification-daemon" or true;
  enabled = h.services.blueman-applet.enable;
  unit = h.systemd.user.services.blueman-applet or {};
  startup = h.wayland.windowManager.hyprland.settings.on;
  autostart = h.xdg.configFile."autostart/blueman.desktop".text or "";
}'''
config = json.loads(subprocess.check_output([
    "nix", "eval", "--json", ".#nixosConfigurations.endeavour.config",
    "--apply", projection,
], text=True))
assert config["dialogs"] is False, "Blueman must use actionable dialogs"
assert "blueman-applet" not in json.dumps(config["startup"]), "Hyprland must not launch a second applet"
assert config["enabled"], "Blueman must be managed by the user service"
unit = config["unit"]
assert "graphical-session.target" in unit["Install"]["WantedBy"]
assert "graphical-session.target" in unit["Unit"]["After"]
assert "graphical-session.target" in unit["Unit"]["PartOf"]
assert unit["Service"]["Type"] == "dbus"
assert unit["Service"]["BusName"] == "org.blueman.Applet"
assert unit["Service"]["Restart"] == "on-failure"
assert "Hidden=true" in config["autostart"], "XDG must not start a second applet"
print("PASS: Bluetooth dialogs and supervised session configuration")
