"""Bind independent-window and safe-transition scenarios to evaluated Nix."""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SESSIONS = {}
for prefix, workspace in (("w", 2), ("l", 7)):
    SESSIONS.update({f"{prefix}{i}": workspace for i in range(1, 9)})

class Configuration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        expression = '''c: let h = c.home-manager.users.erik; in {
          units = builtins.listToAttrs (map (name: {
            inherit name; value = h.systemd.user.services.${name};
          }) (builtins.filter (name: builtins.match "(desktop-.*|tmux-save.*)" name != null)
            (builtins.attrNames h.systemd.user.services)));
          timers = h.systemd.user.timers;
          linger = c.users.users.erik.linger;
          rules = h.wayland.windowManager.hyprland.settings.window_rule;
          workspaceRules = h.wayland.windowManager.hyprland.settings.workspace_rule;
          lua = h.xdg.configFile."hypr/hyprland.lua".text;
          binds = h.wayland.windowManager.hyprland.settings.bind;
          hooks = h.wayland.windowManager.hyprland.settings.on;
          terminal = h.wayland.windowManager.hyprland.settings.terminal;
          editor = h.wayland.windowManager.hyprland.settings.terminalEditor or {};
          yazi = h.wayland.windowManager.hyprland.settings.fileManagerTui;
          tmuxConfig = h.xdg.configFile."tmux/desktop-workspaces.conf".text or "";
        }'''
        result = subprocess.run(["nix", "eval", "--json",
            ".#nixosConfigurations.endeavour.config", "--apply", expression],
            cwd=ROOT, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        cls.config = json.loads(result.stdout)

    def test_default_layout_and_monitor_rules_are_preserved(self):
        rules = self.config["workspaceRules"]
        self.assertFalse(any(rule.get("layout") == "lua:workspace-grid" for rule in rules))
        self.assertTrue(any(rule["workspace"] == "1" and rule.get("monitor") for rule in rules))
        self.assertNotIn("hl.layout.register(", self.config["lua"])

    def test_one_server_and_sixteen_independent_window_units(self):
        """Independent defaults and backend ownership."""
        units = self.config["units"]
        self.assertIn("desktop-tmux", units, "foreground tmux backend missing")
        backend = units["desktop-tmux"]
        command = str(backend["Service"]["ExecStart"])
        self.assertIn("tmux -D -L workspace-desktop", command)
        self.assertNotIn("start-server", command)
        self.assertEqual(backend["Unit"]["X-SwitchMethod"], "keep-old")
        self.assertFalse(backend["Unit"].get("PartOf"))
        self.assertFalse(backend["Unit"].get("BindsTo"))
        self.assertTrue(self.config["linger"])
        for setting in ("exit-empty off", "exit-unattached off", "destroy-unattached off"):
            self.assertIn(setting, self.config["tmuxConfig"])
        self.assertEqual({n for n in units if n.startswith("desktop-window-")},
                         {f"desktop-window-{n}" for n in SESSIONS})
        for name in SESSIONS:
            frontend = units[f"desktop-window-{name}"]
            self.assertIn("desktop-tmux.service", frontend["Unit"]["Requires"])
            self.assertIn("desktop-tmux.service", frontend["Unit"]["After"])
            self.assertIn("graphical-session.target", frontend["Unit"]["PartOf"])
            self.assertEqual(frontend["Service"].get("Restart", "no"), "no")
            self.assertIn(f"bootstrap {name}", str(frontend["Service"]["ExecStartPre"]))
            self.assertIn(f"tmux -N -L workspace-desktop attach-session -t ={name}",
                          str(frontend["Service"]["ExecStart"]))

    def test_sessions_are_saved_and_restored_across_reboots(self):
        """Resurrect snapshot is restored at server start and saved periodically."""
        backend = self.config["units"]["desktop-tmux"]
        self.assertIn("desktop-workspaces restore", str(backend["Service"]["ExecStartPost"]))
        self.assertIn("@resurrect-dir", self.config["tmuxConfig"])
        self.assertIn("resurrect.tmux", self.config["tmuxConfig"])
        self.assertIn("desktop-workspaces save", json.dumps(self.config["units"]["tmux-save"]["Service"]["ExecStart"]))
        shutdown = self.config["units"]["tmux-save-shutdown"]
        self.assertIn("shutdown.target", shutdown["Unit"]["Before"])
        self.assertIn("shutdown.target", shutdown["Install"]["WantedBy"])
        timer = self.config["timers"]["tmux-save"]
        self.assertEqual(timer["Timer"]["Unit"], "tmux-save.service")
        self.assertIn("timers.target", timer["Install"]["WantedBy"])

    def test_preserve_old_herdr_backends_during_transition(self):
        """Removing attachment windows must not remove the live servers."""
        for project in ("dataplatform", "homelab"):
            for kind in ("code", "review"):
                name = f"{project}-{kind}"
                backend = self.config["units"][f"desktop-session-{name}"]
                self.assertEqual(backend["Unit"]["X-SwitchMethod"], "keep-old")
                self.assertFalse(backend["Unit"].get("PartOf"))
                self.assertFalse(backend.get("Install", {}).get("WantedBy"))
                self.assertIn(f"--session {name} server", str(backend["Service"]["ExecStart"]))
                self.assertNotIn(f"desktop-window-{name}", self.config["units"])

    def test_sixteen_class_rules_and_both_recovery_triggers(self):
        rules = self.config["rules"]
        for name, workspace in SESSIONS.items():
            matches = [r for r in rules if name in r.get("match", {}).get("class", "")]
            self.assertEqual(len(matches), 1, f"missing stable class rule for {name}")
            self.assertEqual(matches[0]["workspace"], f"{workspace} silent")
        recovery = [b for b in self.config["binds"] if b.get("_args", [None])[0] == "SUPER + SHIFT + R"]
        self.assertEqual(len(recovery), 1)
        self.assertIn("desktop-workspaces recover", json.dumps(recovery))
        self.assertIn("desktop-workspaces recover", json.dumps(self.config["hooks"]))

    def test_route_shortcuts_and_limit_rollout(self):
        self.assertIn("desktop-workspaces launch shell", json.dumps(self.config["terminal"]))
        self.assertIn("desktop-workspaces launch nvim", json.dumps(self.config["editor"]))
        self.assertIn("desktop-workspaces launch yazi", json.dumps(self.config["yazi"]))
        users = {str(p.relative_to(ROOT)) for p in (ROOT / "modules").rglob("*.nix")
                 if "m.home.desktop-workspaces" in p.read_text() or "m.nixos.desktop-workspaces" in p.read_text()}
        self.assertEqual(users, {"modules/hosts/endeavour/default.nix"})

if __name__ == "__main__":
    unittest.main()
