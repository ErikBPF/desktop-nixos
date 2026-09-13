"""Evaluate staging preparation without evaluating or building a host closure."""

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


class AuthentikStaging(unittest.TestCase):
    def test_existing_private_directory_preparation_includes_authentik(self):
        expression = '''let
          module = import ./modules/hosts/kepler/nas.nix { config = {}; };
          host = module.flake.modules.nixos.kepler-nas { pkgs.coreutils = "/coreutils"; };
        in host.systemd.services.cognee-backup-path.script'''
        result = subprocess.run(["nix", "eval", "--raw", "--offline", "--impure", "--expr", expression],
            cwd=ROOT, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("install -d -m 0770 -o erik -g users", result.stdout)
        self.assertIn("install -d -m 0700 -o erik -g users /fast/k8s/authentik-backups", result.stdout)
        self.assertIn("/fast/k8s/cognee-backups", result.stdout)
