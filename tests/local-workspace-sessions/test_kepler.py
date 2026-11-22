"""Remote shell launch contract; run with the existing workspace test suite."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class KeplerShell(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(subprocess.check_output([
            "nix", "eval", "--json", ".#nixosConfigurations", "--apply", '''hosts: {
              script = (builtins.head (builtins.filter (p: p.name == "sk")
                hosts.endeavour.config.home-manager.users.erik.home.packages)).text;
              ssh = "${hosts.endeavour.pkgs.openssh}/bin/ssh";
              tmux = hosts.kepler.config.programs.tmux.enable;
              linger = hosts.kepler.config.users.users.erik.linger;
              killUserProcesses = hosts.kepler.config.services.logind.settings.Login.KillUserProcesses;
              ghosttyTerminfo = builtins.elem hosts.kepler.pkgs.ghostty.terminfo hosts.kepler.config.environment.systemPackages;
            }'''], cwd=ROOT, text=True))

    def invoke(self, arguments, status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shim = root / "ssh"
            shim.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\nsys.exit(' + str(status) + ')\n')
            shim.chmod(0o700)
            script = root / "sk"
            script.write_text(self.config["script"].replace(self.config["ssh"], str(shim)))
            result = subprocess.run(["bash", str(script), *arguments], capture_output=True, text=True)
            return result.returncode, json.loads(result.stdout)

    def test_bare_shortcut_attaches_persistent_plain_shell(self):
        status, args = self.invoke([])
        self.assertEqual(status, 0)
        self.assertEqual(args, ["-t", "kepler", "tmux new-session -A -s development -c /fast/compute/erik/Documents"])

    def test_explicit_command_and_options_remain_ssh_passthrough(self):
        args = ["-o", "BatchMode=yes", "printf", "hello world"]
        self.assertEqual(self.invoke(args), (0, ["kepler", *args]))

    def test_ssh_failure_is_returned_without_local_fallback(self):
        self.assertEqual(self.invoke([], status=255)[0], 255)

    def test_server_has_tmux_and_lingering_user(self):
        self.assertTrue(self.config["tmux"])
        self.assertTrue(self.config["linger"])
        self.assertFalse(self.config["killUserProcesses"])
        self.assertTrue(self.config["ghosttyTerminfo"])
