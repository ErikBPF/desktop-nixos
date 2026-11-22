"""Evaluated topology and mount safety for the new pool-backed copies."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
OPTIONS = """hosts: builtins.mapAttrs (_: host: let c = host.config; in {
  folders = c.services.syncthing.settings.folders;
  rules = c.systemd.tmpfiles.rules;
  unit = c.systemd.services.syncthing.unitConfig;
  bindsTo = c.systemd.services.syncthing.bindsTo;
  after = c.systemd.services.syncthing.after;
  preStart = c.systemd.services.syncthing.preStart;
}) { inherit (hosts) kepler endeavour; }"""


class ComputeFolders(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.hosts = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", ".#nixosConfigurations", "--apply", OPTIONS],
            cwd=ROOT, text=True,
        ))

    def test_independent_copies_with_reciprocal_sharing(self):
        for folder, label in [("ndykv-cjhly", "Downloads"), ("ykxhp-khmz2", "Documents")]:
            with self.subTest(folder=label):
                self.assertIn(folder, self.hosts["kepler"]["folders"])
                remote = self.hosts["kepler"]["folders"][folder]
                local = self.hosts["endeavour"]["folders"][folder]
                self.assertEqual(remote["path"], f"/fast/compute/erik/{label}/")
                self.assertEqual(local["path"], f"/home/erik/{label}/")
                self.assertEqual(remote["devices"], ["endeavour"])
                self.assertEqual(set(local["devices"]), {"discovery", "pathfinder", "orion", "kepler"})
        self.assertNotIn("kepler", self.hosts["endeavour"]["folders"]["xbwsp-zwvsr"]["devices"])
        self.assertEqual(self.hosts["kepler"]["folders"]["tofu-state"]["devices"], ["discovery", "orion"])

    def test_pool_creation_and_daemon_are_mount_guarded(self):
        host = self.hosts["kepler"]
        self.assertEqual(host["unit"].get("RequiresMountsFor"), ["/fast"])
        self.assertEqual(host["unit"].get("AssertPathIsMountPoint"), "/fast")
        self.assertIn("fast.mount", host["bindsTo"])
        self.assertIn("fast.mount", host["after"])
        self.assertFalse(any("/fast/compute/" in r for r in host["rules"]))
        for label in ("Documents", "Downloads"):
            self.assertIn(f"/fast/compute/erik/{label}/", host["preStart"])
        self.assertIn("stignore", host["preStart"])
        self.assertNotIn("stignore-sync-all", host["preStart"])


if __name__ == "__main__":
    unittest.main()
