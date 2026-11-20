"""Check Endeavour prompts and preserve Orion's existing applet startup."""
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

orion = json.loads(subprocess.check_output([
    "nix", "eval", "--json", ".#nixosConfigurations.orion.config",
    "--apply", projection,
], text=True))
assert orion["enabled"] is False, "Orion must retain its existing applet ownership"
assert any(
    event["_args"][0] == "hyprland.start"
    and 'hl.exec_cmd("blueman-applet")' in event["_args"][1]["expr"]
    for event in orion["startup"]
), "Orion must retain the direct Hyprland applet launch"
print("PASS: Bluetooth dialogs, supervised session and Orion startup")
