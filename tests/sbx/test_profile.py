from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).parents[2]


class SbxContractTest(unittest.TestCase):
    def test_sbx_package_is_pinned_and_runnable(self):
        module = (ROOT / "modules/packages/sbx.nix").read_text()

        self.assertIn('packages.sbx', module)
        self.assertIn('version = "0.39.0";', module)
        self.assertIn("github.com/docker/sbx-releases/releases/download", module)
        self.assertIn('hash = "sha256-LsRbx5OMIML0Bv6MxyKUrVqVS9wEdgFIS4m/GhCDEdQ=";', module)
        self.assertIn('allowUnfreePredicate = pkg: lib.getName pkg == "docker-sbx";', module)
        self.assertIn('system == "x86_64-linux"', module)
        self.assertIn("pkgs.autoPatchelfHook", module)
        self.assertIn("pkgs.e2fsprogs", module)


    def test_repo_profile_uses_an_isolated_clone_with_bounded_resources(self):
        profile = yaml.safe_load((ROOT / ".sbxenv.yaml").read_text())

        self.assertEqual(
            profile,
            {
                "schemaVersion": "1",
                "name": "desktop-nixos-codex",
                "agent": "codex",
                "workspace": {"path": ".", "clone": True},
                "sandboxOptions": {"cpus": 4, "memory": "8g"},
            },
        )
