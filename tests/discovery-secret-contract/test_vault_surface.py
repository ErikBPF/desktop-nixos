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
JUSTFILE = ROOT / "justfile"


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
            self.assertEqual(
                contract["service_identity"],
                {"group": "root", "runtime_directory": "/run/vault-agent", "unit": "vault-agent.service", "user": "root"},
            )
            self.assertTrue(all("perms" in render for render in contract["renders"]))
            tools = next(
                render for render in contract["renders"]
                if render["destination"] == "/run/vault-agent/tools.env"
            )
            self.assertEqual(tools["perms"], "0440")
            self.assertEqual(tools["group"], "docker")
            self.assertIn('command = ["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/tools.env"]', SOURCE.read_text())
            rendered = generated.read_text()
            self.assertNotIn(".Data.data", rendered)
            self.assertNotIn("{{", rendered)

    def test_tools_render_has_value_free_live_verification_recipe(self):
        justfile = JUSTFILE.read_text()
        self.assertIn("verify-tools-secret-render:", justfile)
        self.assertIn("sudo -u erik head -c0 /run/vault-agent/tools.env", justfile)
        self.assertIn("sudo -u nobody head -c0 /run/vault-agent/tools.env", justfile)
        self.assertIn("sudo stat -c", justfile)
        self.assertIn("440 root docker", justfile)


if __name__ == "__main__":
    unittest.main()
