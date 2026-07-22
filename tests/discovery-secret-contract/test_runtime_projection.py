#!/usr/bin/env python3
"""Profile-atomic SecretSpec runtime projection contract."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import tempfile
import time
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/server/_secretspec-runtime-projection.py"
ORCHESTRATION = ROOT / "modules/server/orchestration.nix"
VAULT = ROOT / "modules/hosts/discovery/vault.nix"
COMPOSE = ROOT / "modules/hosts/discovery/compose.nix"
JUSTFILE = ROOT / "justfile"


class RuntimeProjectionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        (self.root / "secretspec.toml").write_text(
            '[profiles.homepage]\nA = { required = true }\nB = { required = true }\n'
        )
        (self.root / ".env").write_text("# config\nPORT=8080\nA=legacy-a\nB=legacy-b\n")
        (self.root / "one.env").write_text("A=sentinel-a\n")
        (self.root / "two.env").write_text("B=sentinel-b\n")

    def tearDown(self):
        self.temporary.cleanup()

    def run_projection(
        self, *sources: str, max_age: int = 900, source_config_names=(),
        ignored_source_names=(), legacy_secret_names=(),
    ):
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
        for name in ignored_source_names:
            command.extend(["--ignored-source-name", name])
        for name in legacy_secret_names:
            command.extend(["--legacy-secret-name", name])
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

    def test_declared_shared_source_surplus_is_emitted_nowhere(self):
        (self.root / "two.env").write_text("B=sentinel-b\nREDIS_PASSWORD=ignored-value\n")
        result = self.run_projection(
            "one.env", "two.env", ignored_source_names=("REDIS_PASSWORD",)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        current = self.root / "runtime/current"
        self.assertEqual((current / "provider.env").read_text(), "A=sentinel-a\nB=sentinel-b\n")
        self.assertNotIn("REDIS_PASSWORD", (current / "config.env").read_text())
        self.assertNotIn("ignored-value", result.stdout + result.stderr)

    def test_can_project_sops_decrypted_secrets_from_legacy_env(self):
        result = self.run_projection(legacy_secret_names=("A", "B"))
        self.assertEqual(result.returncode, 0, result.stderr)
        current = self.root / "runtime/current"
        self.assertEqual((current / "provider.env").read_text(), "A=legacy-a\nB=legacy-b\n")
        self.assertEqual((current / "config.env").read_text(), "# config\nPORT=8080\n")

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
        self.assertIn("secretSpecRuntimeIgnoredSourceNames", source)
        self.assertIn("--ignored-source-name ${n}", source)
        self.assertIn("secretSpecRuntimeLegacySecretNames", source)
        self.assertIn("--legacy-secret-name ${n}", source)
        self.assertIn("lib.optionals (vaultBasenames != [])", source)

    def test_vault_dotenv_renders_publish_a_freshness_witness(self):
        source = VAULT.read_text()
        self.assertIn('static_secret_render_interval = "5m"', source)
        self.assertIn("renderedAt = ''# rendered_at={{ timestamp }}\\n'';", source)
        dotenv_templates = [
            block
            for block in source.split("template {")[1:]
            if 'destination = "/run/vault-agent/' in block
            and '.env"' in block.split("template {", 1)[0]
        ]
        self.assertGreaterEqual(len(dotenv_templates), 12)
        for block in dotenv_templates:
            template = block.split("template {", 1)[0]
            self.assertIn('contents = "${renderedAt}', template)

    def test_media_server_uses_exact_profile_boundary(self):
        source = COMPOSE.read_text()
        self.assertIn('secretSpecRuntimeProfiles."media-server" = "media-server";', source)
        self.assertIn(
            'secretSpecRuntimeIgnoredSourceNames."media-server" = ["REDIS_PASSWORD"];',
            source,
        )

    def test_monitoring_gates_all_secret_consumers(self):
        source = COMPOSE.read_text()
        self.assertIn('secretSpecRuntimeProfiles.monitoring = "monitoring";', source)
        self.assertIn(
            'secretSpecRuntimeSourceConfigNames.monitoring = ["GRAFANA_ADMIN_USER"];',
            source,
        )

    def test_remaining_noncritical_profiles_cut_over_as_one_wave(self):
        source = COMPOSE.read_text()
        expected = [
            'secretSpecRuntimeProfiles.media = "media";',
            'secretSpecRuntimeSourceConfigNames.media = ["NORDVPN_USER" "QBITTORRENT_USER"];',
            'secretSpecRuntimeHealthContainers.media = ["gluetun" "unpackerr" "decluttarr"];',
            'secretSpecRuntimeProfiles.plex = "plex";',
            'secretSpecRuntimeLegacySecretNames.plex = ["PLEX_CLAIM"];',
            'secretSpecRuntimeHealthContainers.plex = ["plex"];',
            'secretSpecRuntimeProfiles."kindle-dash" = "kindle-dash";',
            'secretSpecRuntimeLegacySecretNames."kindle-dash" = [',
            'secretSpecRuntimeHealthContainers."kindle-dash" = ["kindle-dash"];',
            'secretSpecRuntimeProfiles."ai-serving" = "ai-serving";',
            'secretSpecRuntimeSourceConfigNames."ai-serving" = ["LANGFUSE_PUBLIC_KEY" "LANGFUSE_SALT"];',
            'secretSpecRuntimeLegacySecretNames."ai-serving" = ["LITELLM_MASTER_KEY" "OPENCODE_ZEN_KEY"];',
            'secretSpecRuntimeHealthContainers."ai-serving" = ["litellm" "langfuse-clickhouse" "langfuse-web" "langfuse-worker"];',
        ]
        for declaration in expected:
            self.assertIn(declaration, source)
        self.assertIn(
            'secretSpecRuntimeHealthContainers.monitoring = ["grafana" "healthchecks" "scrutiny-influxdb" "scrutiny"];',
            source,
        )

    def test_runtime_health_gate_accepts_all_secret_consumers(self):
        orchestration = ORCHESTRATION.read_text()
        compose = COMPOSE.read_text()
        self.assertIn(
            "type = lib.types.attrsOf (lib.types.listOf lib.types.str);",
            orchestration,
        )
        self.assertIn("for health_container in", orchestration)
        self.assertIn("all_healthy=1", orchestration)
        self.assertIn('secretSpecRuntimeHealthContainers.tools = ["searxng"];', compose)
        self.assertIn(
            'secretSpecRuntimeHealthContainers."media-server" = ["jellystat"];',
            compose,
        )

    def test_tunneling_cutover_has_exact_gate_and_value_free_render_check(self):
        compose = COMPOSE.read_text()
        justfile = JUSTFILE.read_text()
        vault = VAULT.read_text()
        contract = json.loads((ROOT / "modules/hosts/discovery/vault-env-contract.json").read_text())
        self.assertIn('secretSpecRuntimeProfiles.tunneling = "tunneling";', compose)
        self.assertIn(
            'secretSpecRuntimeHealthContainers.tunneling = ["cloudflared"];',
            compose,
        )
        self.assertIn("verify-tunneling-secret-render:", justfile)
        self.assertIn('test "$actual" = CLOUDFLARE_TUNNEL_TOKEN', justfile)
        self.assertIn('["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/tunneling.env"]', vault)
        tunneling = next(row for row in contract["renders"] if row["destination"].endswith("/tunneling.env"))
        self.assertEqual(tunneling["perms"], "0440")

    def test_networking_cutover_has_exact_sources_gates_and_render_check(self):
        compose = COMPOSE.read_text()
        justfile = JUSTFILE.read_text()
        vault = VAULT.read_text()
        contract = json.loads((ROOT / "modules/hosts/discovery/vault-env-contract.json").read_text())
        self.assertIn('secretSpecRuntimeProfiles.networking = "networking";', compose)
        self.assertIn(
            'secretSpecRuntimeLegacySecretNames.networking = ["ADGUARD_PASSWORD"];',
            compose,
        )
        self.assertIn(
            'secretSpecRuntimeHealthContainers.networking = ["swag" "adguard"];',
            compose,
        )
        self.assertIn("verify-networking-secret-render:", justfile)
        self.assertIn('test "$actual" = CLOUDFLARE_API_TOKEN', justfile)
        self.assertIn('["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/networking.env"]', vault)
        networking = next(row for row in contract["renders"] if row["destination"].endswith("/networking.env"))
        self.assertEqual(networking["perms"], "0440")


if __name__ == "__main__":
    unittest.main()
