#!/usr/bin/env python3
"""Owner contract for Discovery Vault Agent dotenv renders."""

from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/hosts/discovery/vault.nix"
EXPORTER = ROOT / "scripts/export-discovery-vault-contract.py"
ARTIFACT = ROOT / "modules/hosts/discovery/vault-env-contract.json"


class DiscoveryVaultSurfaceTest(unittest.TestCase):
    def test_committed_artifact_matches_value_free_source_export(self):
        with tempfile.TemporaryDirectory() as directory:
            generated = pathlib.Path(directory) / "contract.json"
            result = subprocess.run(
                ["python3", str(EXPORTER), "--source", str(SOURCE), "--output", str(generated)],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            contract = json.loads(generated.read_text())
            self.assertEqual(contract, json.loads(ARTIFACT.read_text()))
            self.assertEqual(contract["schema_version"], 1)
            self.assertEqual(contract["owner"], "desktop-nixos")
            self.assertEqual(contract["source"], "modules/hosts/discovery/vault.nix")
            self.assertEqual(len(contract["names"]), 40)
            self.assertEqual(contract["names"], sorted(contract["names"]))
            self.assertIn("CLOUDFLARE_API_TOKEN", contract["names"])
            self.assertIn("HARBOR_ROBOT_SECRET", contract["names"])
            rendered = generated.read_text()
            self.assertNotIn(".Data.data", rendered)
            self.assertNotIn("{{", rendered)


if __name__ == "__main__":
    unittest.main()
