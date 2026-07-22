#!/usr/bin/env python3
"""Profile-atomic SecretSpec runtime projection contract."""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/server/_secretspec-runtime-projection.py"
ORCHESTRATION = ROOT / "modules/server/orchestration.nix"


class RuntimeProjectionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "secretspec.toml").write_text('[profiles]\nhomepage = ["A", "B"]\n')
        (self.root / ".env").write_text("# config\nPORT=8080\nA=legacy-a\nB=legacy-b\n")
        (self.root / "one.env").write_text("A=sentinel-a\n")
        (self.root / "two.env").write_text("B=sentinel-b\n")

    def tearDown(self):
        self.temporary.cleanup()

    def run_projection(self, *sources: str, max_age: int = 900, source_config_names=()):
        command = [
            "python3", str(SCRIPT), "--manifest", str(self.root / "secretspec.toml"),
            "--profile", "homepage", "--legacy-env", str(self.root / ".env"),
            "--output-dir", str(self.root / "runtime"),
            "--max-age-seconds", str(max_age),
        ]
        for source in sources:
            command.extend(["--source", str(self.root / source)])
        for name in source_config_names:
            command.extend(["--source-config-name", name])
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_merges_exact_provider_and_removes_secrets_from_compose_env(self):
        result = self.run_projection("one.env", "two.env")
        self.assertEqual(result.returncode, 0, result.stderr)
        current = self.root / "runtime/current"
        self.assertTrue(current.is_symlink())
        self.assertEqual((current / "provider.env").read_text(), "A=sentinel-a\nB=sentinel-b\n")
        self.assertEqual((current / "config.env").read_text(), "# config\nPORT=8080\n")
        self.assertEqual(os.stat(current / "provider.env").st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(current / "config.env").st_mode & 0o777, 0o600)
        self.assertNotIn("sentinel", result.stdout + result.stderr)

    def test_missing_name_fails_without_outputs(self):
        result = self.run_projection("one.env")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "runtime/current").exists())

    def test_conflicting_duplicate_fails_closed(self):
        (self.root / "two.env").write_text("A=different\nB=sentinel-b\n")
        result = self.run_projection("one.env", "two.env")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("different", result.stdout + result.stderr)

    def test_failed_refresh_preserves_whole_previous_generation(self):
        first = self.run_projection("one.env", "two.env")
        self.assertEqual(first.returncode, 0, first.stderr)
        previous = os.readlink(self.root / "runtime/current")
        (self.root / "two.env").write_text("B=\n")
        second = self.run_projection("one.env", "two.env")
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(os.readlink(self.root / "runtime/current"), previous)
        current = self.root / "runtime/current"
        self.assertEqual((current / "provider.env").read_text(), "A=sentinel-a\nB=sentinel-b\n")
        self.assertEqual((current / "config.env").read_text(), "# config\nPORT=8080\n")

    def test_authoritative_source_config_replaces_legacy_row(self):
        (self.root / ".env").write_text("PORT=8080\nUSER=legacy\nA=legacy-a\nB=legacy-b\n")
        (self.root / "two.env").write_text("B=sentinel-b\nUSER=source-user\n")
        result = self.run_projection("one.env", "two.env", source_config_names=("USER",))
        self.assertEqual(result.returncode, 0, result.stderr)
        current = self.root / "runtime/current"
        self.assertEqual((current / "provider.env").read_text(), "A=sentinel-a\nB=sentinel-b\n")
        self.assertEqual((current / "config.env").read_text(), "PORT=8080\nUSER=source-user\n")
        self.assertNotIn("source-user", result.stdout + result.stderr)

    def test_empty_malformed_and_stale_inputs_fail_closed(self):
        for content in ("A=\nB=sentinel-b\n", "A\nB=sentinel-b\n"):
            (self.root / "one.env").write_text(content)
            result = self.run_projection("one.env")
            self.assertNotEqual(result.returncode, 0)
        (self.root / "one.env").write_text("A=sentinel-a\n")
        old = time.time() - 120
        os.utime(self.root / "one.env", (old, old))
        result = self.run_projection("one.env", "two.env", max_age=60)
        self.assertNotEqual(result.returncode, 0)

    def test_orchestration_uses_only_atomic_runtime_projections(self):
        source = ORCHESTRATION.read_text()
        self.assertIn('runtimeDirectory = "servarr-secretspec-${name}";', source)
        self.assertIn('runtimeOutputDir = "%t/${runtimeDirectory}";', source)
        self.assertIn('runtimeProvider = "${runtimeOutputDir}/current/provider.env";', source)
        self.assertIn('runtimeConfig = "${runtimeOutputDir}/current/config.env";', source)
        self.assertIn("lib.optionals (secretSpecProfile == null) vaultBasenames", source)
        self.assertIn("EnvironmentFile = lib.optional (secretSpecProfile == null)", source)
        self.assertIn("--provider dotenv:${runtimeProvider}", source)
        self.assertIn("--env-file ${composeEnv}", source)
        self.assertIn("--max-age-seconds ${toString cfg.secretSpecRuntimeMaxAgeSeconds}", source)
        self.assertIn("secretSpecRuntimeSourceConfigNames", source)
        self.assertIn("--source-config-name ${n}", source)


if __name__ == "__main__":
    unittest.main()
