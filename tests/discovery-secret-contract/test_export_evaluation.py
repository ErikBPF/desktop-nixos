"""Exercise the exporter through a disposable, evaluated Nix flake."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


EXPORTER = Path(__file__).resolve().parents[2] / "scripts/export-discovery-vault-contract.py"


class ExportEvaluationTest(unittest.TestCase):
    def test_effective_configuration_wins_and_values_are_not_exported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "modules/hosts/discovery/_vault-agent.nix"
            source.parent.mkdir(parents=True)
            source.write_text('''{
  Group = "vault-consumers";
  RuntimeDirectory = "vault-agent";
  hcl = ''
    template {
      contents = "TOKEN={{ .Data.data.TOKEN }}\\nLITERAL=private-sentinel"
      destination = "/run/vault-agent/example.env"
      perms = "0440"
    }
    template {
      contents = "OTHER={{ .Data.data.OTHER }}"
      destination = "/run/vault-agent/override.env"
      perms = "0400"
      exec {
        command = ["/bin/chgrp", "docker", "/run/vault-agent/override.env"]
      }
    }
  '';
}
''')
            shadowed = source.with_name("vault.nix")
            shadowed.write_text('{ Group = "old-group"; }')
            override = root / "override.nix"
            override.write_text('{}')
            (root / "flake.nix").write_text('''{
  outputs = {self}: let
    effective = (import ./modules/hosts/discovery/vault.nix)
      // (import ./modules/hosts/discovery/_vault-agent.nix)
      // (import ./override.nix);
    hcl = builtins.derivation {
      name = "vault-agent.hcl";
      system = "x86_64-linux";
      builder = "/bin/false";
      text = effective.hcl;
    };
  in {
    nixosConfigurations.discovery.config.systemd.services.vault-agent.serviceConfig =
      (builtins.removeAttrs effective ["hcl"]) // {ExecStart = "bao agent -config=${hcl}";};
  };
}
''')

            def export():
                output = root / "contract.json"
                result = subprocess.run(
                    ["python3", str(EXPORTER), "--source", str(source), "--output", str(output)],
                    text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                rendered = output.read_text()
                self.assertNotIn("private-sentinel", rendered)
                self.assertNotIn(".Data.data", rendered)
                self.assertNotIn("{{", rendered)
                return json.loads(rendered)

            original = export()
            self.assertEqual(original["service_identity"]["group"], "vault-consumers")
            self.assertEqual(original["names"], ["OTHER", "TOKEN"])
            self.assertEqual(original["renders"][0]["group"], "vault-consumers")
            self.assertEqual(original["renders"][1]["group"], "docker")
            shadowed.write_text('{ Group = "different-shadowed-group"; }')
            self.assertEqual(export(), original)
            source.write_text(source.read_text().replace('"vault-consumers"', '"active-group"').replace('"0440"', '"0400"'))
            active = export()
            self.assertEqual(active["service_identity"]["group"], "active-group")
            self.assertEqual(active["renders"][0]["perms"], "0400")
            override.write_text('{ Group = "effective-override"; RuntimeDirectory = "effective-runtime"; }')
            effective = export()
            self.assertEqual(effective["source_sha256"], active["source_sha256"])
            self.assertEqual(effective["service_identity"]["group"], "effective-override")
            self.assertEqual(effective["service_identity"]["runtime_directory"], "/run/effective-runtime")
            self.assertEqual(effective["renders"][0]["group"], "effective-override")
            self.assertEqual(effective["renders"][1]["group"], "docker")

    def test_failed_evaluation_does_not_publish_a_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "modules/hosts/discovery/_vault-agent.nix"
            source.parent.mkdir(parents=True)
            source.write_text('{}')
            (root / "flake.nix").write_text('{ invalid Nix }')
            output = root / "contract.json"
            result = subprocess.run(
                ["python3", str(EXPORTER), "--source", str(source), "--output", str(output)],
                text=True, capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
