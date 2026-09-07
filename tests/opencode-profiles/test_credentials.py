"""Check evaluated credential wiring without reading any secret values."""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CredentialProjection(unittest.TestCase):
    def test_orion_projects_only_gateway_credentials(self):
        expression = '''secrets: builtins.map (name: {
          inherit name; inherit (secrets.${name}) mode owner path;
        }) (builtins.filter (name: builtins.match "opencode/.*" name != null)
          (builtins.attrNames secrets))'''
        result = subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.orion.config.sops.secrets", "--apply", expression,
        ], cwd=ROOT, text=True)
        self.assertEqual(json.loads(result), [
            {"name": "opencode/" + name, "mode": "0400", "owner": "erik",
             "path": "/run/secrets/opencode/" + name}
            for name in ("litellm_key", "work_key")
        ])
