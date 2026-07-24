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
TOFU_BACKUP = ROOT / "modules/services/restic-tofu-state.nix"
DISCOVERY = ROOT / "modules/hosts/discovery/default.nix"


class DiscoveryVaultSurfaceTest(unittest.TestCase):
    def test_backblaze_b2_backup_contract(self):
        tofu = TOFU_BACKUP.read_text()
        vault = SOURCE.read_text()
        discovery = DISCOVERY.read_text()

        self.assertIn('sops.templates."restic-b2.env"', tofu)
        self.assertIn("AWS_ACCESS_KEY_ID=", tofu)
        self.assertIn("AWS_SECRET_ACCESS_KEY=", tofu)
        self.assertIn("services.restic.backups.tofu-state-b2", tofu)
        self.assertIn("services.restic.backups.vault-b2", vault)
        self.assertIn("environmentFile =", tofu)
        self.assertIn("environmentFile =", vault)
        self.assertIn("restic_tofu_state_b2_last_success_seconds", tofu)
        self.assertIn("vault_b2_backup_last_success_seconds", vault)
        self.assertIn("restic-backups-tofu-state-b2.onFailure", tofu)
        self.assertIn("restic-backups-vault-b2.onFailure", vault)
        self.assertIn('endpoint = "https://', discovery)
        self.assertIn('bucket = "homelab-vault"', discovery)
        justfile = JUSTFILE.read_text()
        self.assertIn("verify-b2-backups:", justfile)
        self.assertGreaterEqual(justfile.count("check --read-data"), 2)
        self.assertGreaterEqual(justfile.count("dump latest"), 2)
        self.assertIn("| cmp", justfile)

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
            self.assertEqual(len(contract["names"]), 50)
            self.assertIn("ADGUARD_PASSWORD", contract["names"])
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
            ha_harness = next(
                render for render in contract["renders"]
                if render["destination"] == "/run/vault-agent/ha-harness.env"
            )
            self.assertEqual(ha_harness["perms"], "0440")
            self.assertEqual(ha_harness["group"], "docker")
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
        self.assertGreaterEqual(justfile.count("grep -v '^#'"), 2)

    def test_ha_harness_render_has_value_free_live_verification_recipe(self):
        justfile = JUSTFILE.read_text()
        self.assertIn("verify-ha-harness-secret-render:", justfile)
        self.assertIn("seed-kindle-dash-vault:", justfile)
        self.assertIn("verify-kindle-dash-secret-render:", justfile)
        self.assertIn("sudo chgrp docker /run/vault-agent/ha-harness.env", justfile)
        self.assertIn("sudo -u erik head -c0 /run/vault-agent/ha-harness.env", justfile)
        self.assertIn("sudo -u nobody head -c0 /run/vault-agent/ha-harness.env", justfile)
        self.assertIn('sort -u', justfile)
        self.assertIn('HA_HARNESS_TOKEN\\nLITELLM_API_KEY', justfile)

    def test_ha_harness_uses_dedicated_litellm_secret(self):
        for relative in (
            "modules/hosts/discovery/vault.nix",
            "modules/hosts/discovery/_vault-agent.nix",
        ):
            source = (ROOT / relative).read_text()
            self.assertIn('secret \\"secret/data/home/ha-harness-litellm\\"', source)
            self.assertIn('secret \\"secret/data/home/ha-harness\\"', source)
            self.assertIn('["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/ha-harness.env"]', source)

    def test_kindle_dash_runtime_secrets_come_from_vault_agent(self):
        compose = (ROOT / "modules/hosts/discovery/compose.nix").read_text()
        self.assertIn('"kindle-dash" = ["kindle-dash"];', compose)
        self.assertNotIn('secretSpecRuntimeLegacySecretNames."kindle-dash"', compose)
        for relative in (
            "modules/hosts/discovery/vault.nix",
            "modules/hosts/discovery/_vault-agent.nix",
        ):
            source = (ROOT / relative).read_text()
            self.assertIn('secret \\"secret/data/home/kindle-dash\\"', source)
            self.assertIn('destination = "/run/vault-agent/kindle-dash.env"', source)
            self.assertIn(
                '["${pkgs.coreutils}/bin/chgrp", "docker", "/run/vault-agent/kindle-dash.env"]',
                source,
            )

    def test_ai_serving_remaining_runtime_secrets_come_from_vault_agent(self):
        for relative in (
            "modules/hosts/discovery/vault.nix",
            "modules/hosts/discovery/_vault-agent.nix",
        ):
            source = (ROOT / relative).read_text()
            self.assertIn("LITELLM_MASTER_KEY={{ .Data.data.LITELLM_MASTER_KEY }}", source)
            self.assertIn("OPENCODE_ZEN_KEY={{ .Data.data.OPENCODE_ZEN_KEY }}", source)
        justfile = JUSTFILE.read_text()
        self.assertIn("seed-ai-serving-vault:", justfile)
        self.assertIn('echo "ai_serving_vault=seeded keys_added=2"', justfile)
        self.assertIn("verify-ai-serving-secret-render:", justfile)
        self.assertIn(
            'echo "ai_serving_render=ready mode=0440 owner=root group=vault-consumers fresh=true keys=11"',
            justfile,
        )

    def test_pocketid_runtime_secret_comes_from_vault_agent(self):
        vault = SOURCE.read_text()
        netbird = (ROOT / "modules/hosts/discovery/netbird-server.nix").read_text()
        self.assertIn('destination = "/run/vault-agent/netbird-pocketid.env"', vault)
        self.assertIn(
            '"/run/vault-agent/netbird-pocketid.env"',
            netbird,
        )
        self.assertNotIn('sops.secrets."netbird/pocketid_encryption_key"', netbird)
        self.assertIn('after = ["vault-agent.service"]', netbird)
        self.assertIn("[ -s /run/vault-agent/netbird-pocketid.env ]", netbird)
        justfile = JUSTFILE.read_text()
        self.assertIn("seed-netbird-pocketid-vault:", justfile)
        self.assertIn("verify-netbird-pocketid-secret-render:", justfile)

    def test_netbird_controlplane_secrets_come_from_vault_agent(self):
        vault = SOURCE.read_text()
        netbird = (ROOT / "modules/hosts/discovery/netbird-server.nix").read_text()
        for destination in (
            "/run/vault-agent/netbird-postgres.env",
            "/run/vault-agent/netbird-auth.env",
            "/run/vault-agent/netbird-datastore.key",
        ):
            self.assertIn(f'destination = "{destination}"', vault)
            self.assertIn(destination, netbird)
        for name in ("postgres_dsn", "auth_secret", "datastore_enc_key"):
            self.assertNotIn(f'sops.secrets."netbird/{name}"', netbird)
        self.assertEqual(netbird.count("2>/dev/null || true)"), 2)
        justfile = JUSTFILE.read_text()
        self.assertIn("seed-netbird-controlplane-vault:", justfile)
        self.assertIn("verify-netbird-controlplane-secret-render:", justfile)

    def test_hermes_runtime_envs_come_from_vault_agent(self):
        vault = SOURCE.read_text()
        primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
        agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        for destination in (
            "/run/vault-agent/hermes-agent.env",
            "/run/vault-agent/hermes-daedalus.env",
            "/run/vault-agent/hermes-argus.env",
        ):
            self.assertIn(f'destination = "{destination}"', vault)
        self.assertIn('environmentFile = "/run/vault-agent/hermes-agent.env"', primary)
        self.assertIn('environmentFile = "/run/vault-agent/hermes-daedalus.env"', agents)
        self.assertIn('environmentFile = "/run/vault-agent/hermes-argus.env"', agents)
        self.assertNotIn('sops.secrets."hermes_agent/server_env"', primary)
        self.assertNotIn('sops.secrets."hermes_agents/daedalus_env"', agents)
        self.assertNotIn('sops.secrets."hermes_agents/argus_env"', agents)
        justfile = JUSTFILE.read_text()
        self.assertIn("seed-hermes-vault:", justfile)
        self.assertIn("verify-hermes-secret-renders:", justfile)

    def test_hermes_wiki_deploy_key_comes_from_vault_agent(self):
        vault = SOURCE.read_text()
        wiki = (ROOT / "modules/hosts/discovery/hermes-wiki.nix").read_text()
        primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
        self.assertIn('destination = "/run/vault-agent/hermes-wiki.key"', vault)
        self.assertIn('.Data.data.WIKI_DEPLOY_KEY }}{{ end }}\\n"', vault)
        self.assertIn('"/run/vault-agent/hermes-wiki.key:/opt/wiki-key:ro"', primary)
        self.assertIn('keyPath = "/run/vault-agent/hermes-wiki.key"', wiki)
        self.assertIn('extraGroups = ["vault-consumers"]', wiki)
        self.assertNotIn('sops.secrets."hermes_wiki/deploy_key"', wiki)
        self.assertIn('after = ["network-online.target" "nss-lookup.target" "vault-agent.service"]', wiki)
        self.assertIn('[ -s ${keyPath} ] && [ -r ${keyPath} ]', wiki)

    def test_openbao_restore_drill_is_isolated_and_quarterly(self):
        vault = SOURCE.read_text()
        justfile = JUSTFILE.read_text()
        self.assertIn("systemd.services.openbao-restore-drill", vault)
        drill = vault.split("systemd.services.openbao-restore-drill", 1)[1].split(
            "systemd.timers.openbao-restore-drill", 1
        )[0]
        self.assertIn("path = [pkgs.bash]", drill)
        self.assertIn('RuntimeDirectory = "openbao-restore-drill"', drill)
        self.assertIn('Environment = "HOME=/run/openbao-restore-drill"', drill)
        self.assertIn("127.0.0.1:18200", vault)
        self.assertIn("mktemp -d /var/tmp/openbao-restore-drill.", vault)
        self.assertIn("operator raft snapshot restore -force", vault)
        self.assertIn("/run/secrets/vault_unseal_key", vault)
        self.assertIn('.auth.client_token | type == "string" and length > 0', drill)
        self.assertNotIn(".auth.metadata", drill)
        self.assertNotIn("/v1/auth/token/lookup-self", drill)
        self.assertNotIn("/v1/secret/data/shared/discord", drill)
        self.assertIn("systemd.timers.openbao-restore-drill", vault)
        self.assertIn('OnCalendar = "*-01,04,07,10-01 05:30:00"', vault)
        self.assertIn("openbao-restore-drill:", justfile)
        self.assertIn("systemctl status openbao-restore-drill.service --no-pager || true", justfile)


if __name__ == "__main__":
    unittest.main()
