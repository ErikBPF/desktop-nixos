"""Remote shell launch contract; run with the existing workspace test suite."""
import json
import os
from pathlib import Path
import pty
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
              coordinator = "${hosts.endeavour.config.home-manager.users.erik.home.profileDirectory}/bin/desktop-workspaces";
              tmux = hosts.kepler.config.programs.tmux.enable;
              recoveryTmux = hosts.kepler-cp1-recovery.config.programs.tmux.enable;
              recoveryBootCounting = hosts.kepler-cp1-recovery.config.boot.loader.systemd-boot.bootCounting.enable;
              recoveryPicker = builtins.any (p: p.name == "tmux-resume") hosts.kepler-cp1-recovery.config.environment.systemPackages;
              linger = hosts.kepler.config.users.users.erik.linger;
              killUserProcesses = hosts.kepler.config.services.logind.settings.Login.KillUserProcesses;
              ghosttyTerminfo = builtins.elem hosts.kepler.pkgs.ghostty.terminfo hosts.kepler.config.environment.systemPackages;
            }'''], cwd=ROOT, text=True))

    def _script(self, directory, status=0):
        root = Path(directory)
        shim = root / "ssh"
        shim.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\nsys.exit(' + str(status) + ')\n')
        shim.chmod(0o700)
        script = root / "sk"
        script.write_text(self.config["script"].replace(self.config["ssh"], str(shim)).replace(self.config["coordinator"], str(shim)))
        return script

    def invoke(self, arguments, status=0):
        with tempfile.TemporaryDirectory() as directory:
            script = self._script(directory, status)
            result = subprocess.run(["bash", str(script), *arguments], capture_output=True, text=True)
            return result.returncode, json.loads(result.stdout)

    def invoke_with_terminal(self, arguments, status=0, tty_stdout=True):
        with tempfile.TemporaryDirectory() as directory:
            script = self._script(directory, status)
            master, slave = pty.openpty()
            try:
                if tty_stdout:
                    process = subprocess.Popen(["bash", str(script), *arguments], stdin=slave, stdout=slave, stderr=slave)
                    os.close(slave)
                    slave = None
                    chunks = []
                    while True:
                        try:
                            chunk = os.read(master, 4096)
                        except OSError:
                            break
                        if not chunk:
                            break
                        chunks.append(chunk)
                    process.wait()
                    output = b"".join(chunks).decode()
                else:
                    process = subprocess.Popen(
                        ["bash", str(script), *arguments],
                        stdin=slave,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                    )
                    os.close(slave)
                    slave = None
                    output, _ = process.communicate()
            finally:
                for fd in (slave, master):
                    if fd is not None:
                        os.close(fd)
            lines = [line.strip() for line in output.replace("\r", "").splitlines() if line.strip().startswith("[")]
            return process.returncode, json.loads(lines[-1])

    def test_bare_shortcut_opens_session_picker(self):
        status, args = self.invoke([])
        self.assertEqual(status, 0)
        self.assertEqual(args, ["remote"])

    def test_piped_command_keeps_non_tty_passthrough(self):
        args = ["-o", "BatchMode=yes", "printf", "hello world"]
        self.assertEqual(self.invoke(args), (0, ["kepler", *args]))

    def test_interactive_command_requests_tty(self):
        args = ["-o", "BatchMode=yes", "printf", "hello world"]
        self.assertEqual(self.invoke_with_terminal(args), (0, ["-o", "RequestTTY=yes", "kepler", *args]))

    def test_redirected_stdout_keeps_non_tty_passthrough(self):
        args = ["-o", "BatchMode=yes", "printf", "hello world"]
        self.assertEqual(self.invoke_with_terminal(args, tty_stdout=False), (0, ["kepler", *args]))

    def test_ssh_failure_is_returned_without_local_fallback(self):
        self.assertEqual(self.invoke([], status=255)[0], 255)

    def test_server_has_tmux_and_lingering_user(self):
        self.assertTrue(self.config["tmux"])
        self.assertTrue(self.config["linger"])
        self.assertFalse(self.config["killUserProcesses"])
        self.assertTrue(self.config["ghosttyTerminfo"])

    def test_recovery_host_keeps_containment_and_gets_same_tools(self):
        self.assertTrue(self.config["recoveryTmux"])
        self.assertTrue(self.config["recoveryPicker"])
        self.assertFalse(self.config["recoveryBootCounting"])
