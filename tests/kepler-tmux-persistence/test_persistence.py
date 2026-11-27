"""Kepler's default tmux server restores and saves sessions."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
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
              serverWantedBy = c.systemd.user.services.kepler-tmux.wantedBy;
              defaults = let unit = c.systemd.services.kepler-tmux-defaults or null;
                in if unit == null then null else {
                  inherit (unit) script wantedBy after requires environment unitConfig serviceConfig;
                };
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

    def test_boot_waits_for_storage_before_starting_the_managed_server(self):
        unit = self.config["defaults"]
        self.assertIsNotNone(unit, "Kepler has no default-session boot unit")
        self.assertIn("multi-user.target", unit["wantedBy"])
        self.assertIn("user@1000.service", unit["requires"])
        self.assertIn("user@1000.service", unit["after"])
        self.assertIn("zfs-mount.service", unit["after"])
        self.assertEqual(unit["unitConfig"]["AssertPathIsMountPoint"], "/fast")
        self.assertEqual(unit["unitConfig"]["RequiresMountsFor"], [
            "/fast/compute/erik/Documents/erik/homelab",
            "/fast/compute/erik/Documents/nstech/dataplatform",
        ])
        self.assertEqual(unit["serviceConfig"]["User"], "erik")
        self.assertEqual(unit["environment"]["TMUX_TMPDIR"], "/run/user/1000")
        self.assertEqual(unit["environment"]["XDG_RUNTIME_DIR"], "/run/user/1000")
        self.assertNotIn("default.target", self.config["serverWantedBy"], "Restore must not race the mount-ordered boot unit")

    def test_default_sessions_use_the_managed_socket_and_preserve_restored_panes(self):
        unit = self.config["defaults"]
        self.assertIsNotNone(unit, "Kepler has no default-session boot unit")
        self.assertEqual(unit["environment"].get("TMUX_TMPDIR"), "/run/user/1000")
        tmux = shutil.which("tmux")
        self.assertIsNotNone(tmux, "Real tmux is required for the startup check")
        with tempfile.TemporaryDirectory(prefix="kepler defaults ") as temporary:
            root = Path(temporary)
            runtime, homelab, dataplatform, restored = [root / name for name in ("runtime", "homelab", "dataplatform", "restored")]
            for directory in (runtime, homelab, restored):
                directory.mkdir()
            config = root / "tmux.conf"
            config.write_text("set -g exit-empty off\n")
            command = [tmux, "-f", str(config)]
            wrapper = root / "tmux"
            wrapper.write_text("#!/bin/sh\nexec " + shlex.join(command) + ' "$@"\n')
            wrapper.chmod(0o700)
            owner = root / "systemctl"
            owner.write_text(f'''#!{sys.executable}
import os, pathlib, subprocess, sys
assert sys.argv[1:] == ["--user", "start", "kepler-tmux.service"]
if os.environ.get("TEST_OWNER") == "fail": sys.exit(1)
if os.environ.get("TEST_OWNER") == "absent": sys.exit(0)
pathlib.Path({str(root / "owner-called")!r}).touch()
subprocess.run(["tmux", "start-server"], check=True)
if pathlib.Path({str(root / "restore-l1")!r}).exists() and subprocess.run(["tmux", "-N", "has-session", "-t", "=l1"], capture_output=True).returncode:
    subprocess.run(["tmux", "-N", "new-session", "-d", "-s", "l1", "-c", {str(restored)!r}], check=True)
''')
            owner.chmod(0o700)
            environment = os.environ | unit["environment"] | {
                "PATH": f"{root}:{os.environ['PATH']}", "SHELL": "/bin/sh",
                "TMUX_TMPDIR": str(runtime), "XDG_RUNTIME_DIR": str(runtime),
            }
            environment.pop("TMUX", None)
            script = unit["script"].replace(
                "/fast/compute/erik/Documents/erik/homelab", shlex.quote(str(homelab))
            ).replace("/fast/compute/erik/Documents/nstech/dataplatform", shlex.quote(str(dataplatform)))

            def start(mode=""):
                return subprocess.run(["bash", "-eu", "-c", script], env=environment | {"TEST_OWNER": mode}, capture_output=True, text=True)

            def tmux_run(*arguments):
                return subprocess.run([*command, "-N", *arguments], env=environment, capture_output=True, text=True)

            def panes():
                result = tmux_run("list-panes", "-a", "-F", "#{session_name}\t#{session_path}\t#{pane_current_path}\t#{session_id}\t#{pane_id}\t#{pane_pid}")
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout

            try:
                missing = start()
                self.assertNotEqual(missing.returncode, 0)
                self.assertIn("Project directory is unavailable", missing.stderr)
                self.assertFalse((root / "owner-called").exists())
                dataplatform.mkdir()
                for failure in ("fail", "absent"):
                    self.assertNotEqual(start(failure).returncode, 0)
                    self.assertNotEqual(tmux_run("list-sessions").returncode, 0, "Seeder must not start an unmanaged server")
                first = start()
                self.assertEqual(first.returncode, 0, first.stderr)
                actual = {fields[0]: fields[1:3] for fields in (line.split("\t") for line in panes().splitlines())}
                expected = {f"{prefix}{i}": [str(folder), str(folder)] for prefix, folder in [("l", homelab), ("w", dataplatform)] for i in range(1, 11)}
                self.assertEqual(actual, expected)
                self.assertEqual(tmux_run("new-session", "-d", "-s", "manual", "-c", str(restored)).returncode, 0)
                self.assertEqual(tmux_run("kill-session", "-t", "=l1").returncode, 0)
                (root / "restore-l1").touch()
                filled = start()
                self.assertEqual(filled.returncode, 0, filled.stderr)
                self.assertIn(f"l1\t{restored}\t{restored}\t", panes(), "Existing restoration must finish before defaults are filled")
                before = panes()
                again = start()
                self.assertEqual(again.returncode, 0, again.stderr)
                self.assertEqual(panes(), before, "Reruns must preserve every session ID and pane PID")
            finally:
                tmux_run("kill-server")


if __name__ == "__main__":
    unittest.main()
