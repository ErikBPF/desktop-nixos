"""Kepler's default tmux server restores and saves sessions."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class KeplerTmuxPersistence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(subprocess.check_output([
            "nix", "eval", "--json", ".#nixosConfigurations.kepler.config", "--apply", '''c: {
              plugins = map (p: p.name or "") c.programs.tmux.plugins;
              tmuxConfig = c.programs.tmux.extraConfig;
              server = c.systemd.user.services.kepler-tmux.serviceConfig;
              save = c.systemd.user.services.kepler-tmux-save.serviceConfig;
              timer = c.systemd.user.timers.kepler-tmux-save.timerConfig;
              socketEnv = c.environment.variables.TMUX_TMPDIR or "";
              secureSocket = c.programs.tmux.secureSocket;
            }'''], cwd=ROOT, text=True))

    def test_server_restores_before_clients_attach(self):
        condition = self.config["server"]["ExecCondition"]
        self.assertIn("! ", condition)
        self.assertIn("tmux -N list-sessions", condition)
        self.assertIn("resurrect", " ".join(self.config["plugins"]))
        self.assertIn("exit-empty off", self.config["tmuxConfig"])
        self.assertIn("@resurrect-dir", self.config["tmuxConfig"])
        self.assertTrue(self.config["server"]["ExecStart"].endswith("tmux -D"))
        self.assertIn("TMUX_TMPDIR=%t", self.config["server"]["Environment"])
        self.assertTrue(any(item.startswith("PATH=") for item in self.config["server"]["Environment"]))
        restore = Path(self.config["server"]["ExecStartPost"].lstrip("-"))
        self.assertTrue(restore.name.endswith("kepler-tmux-restore"))
        source = (ROOT / "modules/hosts/kepler/tmux-persistence.nix").read_text()
        self.assertIn("show-options", source)
        self.assertIn("-N run-shell", source)
        self.assertIn("restore.sh", source)

    def test_save_runs_periodically_and_when_the_server_stops(self):
        self.assertIn("tmux -N run-shell", self.config["save"]["ExecStart"])
        self.assertIn("tmux -N has-session", self.config["save"]["ExecCondition"])
        self.assertIn("TMUX_TMPDIR=%t", self.config["save"]["Environment"])
        self.assertIn("tmux -N run-shell", self.config["server"]["ExecStop"])
        self.assertIn("save.sh", self.config["server"]["ExecStop"])
        self.assertEqual(self.config["timer"]["Unit"], "kepler-tmux-save.service")

    def test_kepler_default_socket_is_used(self):
        for command in ("ExecStart", "ExecStop"):
            self.assertNotIn(" -L ", self.config["server"][command])
        self.assertNotIn(" -L ", self.config["save"]["ExecStart"])
        self.assertTrue(self.config["secureSocket"])
        # secureSocket exports this through /etc/set-environment.
        self.assertIn("/run/user/", self.config["socketEnv"])
        self.assertIn('@resurrect-dir "/home/', self.config["tmuxConfig"])


if __name__ == "__main__":
    unittest.main()
