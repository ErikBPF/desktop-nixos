"""Exercise the owner Just entrypoint and remote shell without any live access."""

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
REPOSITORY = "harbor.homelab.pastelariadev.com/ha-harness/ha-harness"
IMAGE = REPOSITORY + "@sha256:" + "a" * 64  # Synthetic fixture, not a published image.
DOCKER = "/run/current-system/sw/bin/docker"


class ReaderProof(unittest.TestCase):
    def setUp(self):
        self.assertIn("\nverify-ha-harbor-reader image:", (ROOT / "justfile").read_text())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "scripts").mkdir()
        shutil.copy(ROOT / "justfile", self.root / "justfile")
        shutil.copy(ROOT / "scripts/verify-ha-harbor-reader.sh", self.root / "scripts")
        (self.root / "fleet.json").write_text(json.dumps({"hosts": {"discovery": {"ip": "192.0.2.42"}}}))
        (self.root / ".env").write_text("DO_NOT_LOAD=owner-reader-test\n")
        self.log = self.root / "calls.jsonl"
        self.mode = self.root / "mode"
        self.mode.write_text("success")
        self.fake("ssh", f"""
import json, pathlib, subprocess, sys
with open({str(self.log)!r}, 'a') as log:
    log.write(json.dumps(['ssh'] + sys.argv[1:]) + '\\n')
host = sys.argv.index('erik@192.0.2.42')
result = subprocess.run(' '.join(sys.argv[host + 1:]), shell=True,
                        executable={shutil.which('bash')!r}, input=sys.stdin.read(), text=True)
sys.exit(result.returncode)
""")
        self.fake("sudo", f"""
import json, subprocess, sys
with open({str(self.log)!r}, 'a') as log:
    log.write(json.dumps(['sudo'] + sys.argv[1:]) + '\\n')
expected = ['-n', 'env', '-i', 'HOME=/root', 'PATH=/run/current-system/sw/bin',
            '/run/current-system/sw/bin/timeout', '--signal=KILL', '300',
            '/run/current-system/sw/bin/bash', '-s', '--', {IMAGE!r}]
assert sys.argv[1:] == expected, sys.argv[1:]
payload = sys.stdin.read()
assert {DOCKER!r} in payload
# Only substitute executable paths at this fake process boundary.
payload = payload.replace({DOCKER!r}, {str(self.bin / 'docker')!r})
payload = payload.replace(' | grep ', ' | ' + {shlex.quote(shutil.which('grep'))!r} + ' ')
command = [{shutil.which('env')!r}] + sys.argv[3:]
command[4] = {shutil.which('timeout')!r}
command[7] = {shutil.which('bash')!r}
sys.exit(subprocess.run(command, input=payload, text=True).returncode)
""")
        self.fake("docker", f"""
import json, os, pathlib, sys
args = sys.argv[1:]
with open({str(self.log)!r}, 'a') as log:
    log.write(json.dumps(['docker'] + args) + '\\n')
assert args[:4] == ['--config', '/run/harbor-reader', '--host', 'unix:///run/docker.sock']
assert os.environ['HOME'] == '/root'
assert os.environ['PATH'] == '/run/current-system/sw/bin'
assert 'DOCKER_HOST' not in os.environ and 'DOCKER_CONFIG' not in os.environ
mode = pathlib.Path({str(self.mode)!r}).read_text()
if args[4:] == ['image', 'pull', {IMAGE!r}]:
    print('Already cached; untrusted child output must not escape')
    print('simulated credential-shaped diagnostic', file=sys.stderr)
    sys.exit(1 if mode == 'pull-fail' else 0)
assert args[4:] == ['image', 'inspect', '--format', '{{{{range .RepoDigests}}}}{{{{println .}}}}{{{{end}}}}', {IMAGE!r}], args
print({IMAGE!r} if mode != 'wrong-digest' else {REPOSITORY + '@sha256:' + 'b' * 64!r})
if mode == 'inspect-fail':
    print('simulated private diagnostic', file=sys.stderr)
    sys.exit(1)
""")
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "DOCKER_HOST": "tcp://untrusted.invalid:2375", "DOCKER_CONFIG": "/nonexistent-test-config"}

    def fake(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o700)

    def run_reader(self, image=IMAGE):
        return subprocess.run(
            ["just", "--no-dotenv", "--quiet", "verify-ha-harbor-reader", image],
            cwd=self.root, env=self.env, text=True, capture_output=True, timeout=10,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_exact_digest_uses_managed_config_and_clean_rootful_remote(self):
        result = self.run_reader()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"imageDigest={IMAGE}\npulled using configured managed-reader auth path\n")
        self.assertEqual(result.stderr, "")
        ssh = self.calls()[0]
        for option in ["BatchMode=yes", "StrictHostKeyChecking=yes", "ForwardAgent=no", "ConnectTimeout=8"]:
            self.assertIn(option, ssh)
        self.assertIn("2222", ssh)
        self.assertIn("erik@192.0.2.42", ssh)
        self.assertEqual(shlex.split(ssh[-1])[-1], IMAGE)

    def test_invalid_references_never_reach_ssh(self):
        for image in [REPOSITORY + ":latest", IMAGE.replace("ha-harness/ha-harness", "library/other"),
                      IMAGE.replace("harbor.homelab", "harborXhomelab"),
                      IMAGE.upper(), IMAGE[:-1], IMAGE + "\n", IMAGE + "; touch INJECTED",
                      "$(touch INJECTED)", "'$(touch INJECTED)'", "--help"]:
            with self.subTest(image=image):
                result = self.run_reader(image)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.calls(), [])
                self.assertFalse((self.root / "INJECTED").exists())

    def test_pull_failure_does_not_inspect_or_expose_child_output(self):
        self.mode.write_text("pull-fail")
        result = self.run_reader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("managed-reader pull verification failed", result.stderr)
        self.assertNotIn("simulated", result.stderr)
        self.assertEqual(len([call for call in self.calls() if call[0] == "docker"]), 1)

    def test_wrong_digest_fails(self):
        self.mode.write_text("wrong-digest")
        result = self.run_reader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_failed_inspect_cannot_pass_from_partial_matching_output(self):
        self.mode.write_text("inspect-fail")
        result = self.run_reader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("simulated", result.stderr)

    def test_cached_image_still_pulls_before_each_inspect(self):
        for _ in range(2):
            result = self.run_reader()
            self.assertEqual(result.returncode, 0, result.stderr)
        docker = [call for call in self.calls() if call[0] == "docker"]
        self.assertEqual([call[6] for call in docker], ["pull", "inspect", "pull", "inspect"])

    def test_remote_emulation_without_nixos_system_profile(self):
        self.assertIsNotNone(shutil.which("grep"), "Local grep must be available")
        remote_path = str(self.root / "absent-nixos-system-profile")
        sudo = self.bin / "sudo"
        # Keep original production argv assertions; alter only the emulated PATH.
        sudo.write_text(sudo.read_text().replace(
            "command[4] =", f"command[3] = {'PATH=' + remote_path!r}\ncommand[4] ="
        ).replace(
            "sys.exit(subprocess.run(command, input=payload, text=True).returncode)",
            "result = subprocess.run(command, input=payload, text=True, capture_output=True)\n"
            f"with open({str(self.log)!r}, 'a') as log:\n"
            "    log.write(json.dumps(['remote-stderr', result.stderr]) + '\\n')\n"
            "sys.exit(result.returncode)",
        ))
        docker = self.bin / "docker"
        docker.write_text(docker.read_text().replace(
            "assert os.environ['PATH'] == '/run/current-system/sw/bin'",
            f"assert os.environ['PATH'] == {remote_path!r}",
        ))
        result = self.run_reader()
        diagnostics = "\n".join(call[1] for call in self.calls() if call[0] == "remote-stderr")
        self.assertEqual(result.returncode, 0, result.stderr + diagnostics)


if __name__ == "__main__":
    unittest.main()
