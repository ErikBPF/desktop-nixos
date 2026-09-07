"""Run: python3 -m unittest discover -s tests/syncthing-ignore"""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
OPTIONS = """hosts: builtins.mapAttrs (_: host: let c = host.config; in {
  rules = c.systemd.tmpfiles.rules;
  triggers = c.systemd.services.syncthing.restartTriggers;
  after = c.systemd.services.syncthing.after;
}) { inherit (hosts) orion apollo discovery kepler pathfinder endeavour; }"""


class IgnoreActivation(unittest.TestCase):
    def test_every_deployed_ignore_restarts_after_tmpfiles(self):
        hosts = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", ".#nixosConfigurations", "--apply", OPTIONS],
            cwd=ROOT, text=True,
        ))
        for name, host in hosts.items():
            with self.subTest(host=name):
                targets = {r.split()[-1] for r in host["rules"]
                           if r.startswith("L+ ") and ".stignore " in r}
                self.assertTrue(targets)
                self.assertTrue(targets <= set(host["triggers"]))
                self.assertIn("systemd-tmpfiles-resetup.service", host["after"])


if __name__ == "__main__":
    unittest.main()
