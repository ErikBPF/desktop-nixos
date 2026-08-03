#!/usr/bin/env python3
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class ArgusSecurityContract(unittest.TestCase):
    def test_argus_disables_terminal_tools(self):
        source = (
            ROOT / "modules/hosts/discovery/hermes-agents.nix"
        ).read_text()
        argus = source.split(
            "services.hermes-agent-oci-argus = {", 1
        )[1]
        healthcheck = source.split(
            "systemd.services.hermes-argus-healthcheck", 1
        )[1]
        self.assertIn('agent.disabled_toolsets = ["terminal" "kanban"];', argus)
        self.assertIn("discord = [];", argus)
        self.assertIn("webhook = [];", argus)
        self.assertNotIn("terminal = false;", argus)
        self.assertIn("/opt/hermes/.venv/bin/python", healthcheck)
        self.assertIn('"terminal" in cfg["agent"]["disabled_toolsets"]', healthcheck)
        self.assertIn('not _get_platform_tools(cfg,"discord")', healthcheck)
        self.assertIn('not _get_platform_tools(cfg,"webhook")', healthcheck)

    def test_homelab_agent_identity_is_cleytin(self):
        soul = (ROOT / "modules/hosts/discovery/argus-SOUL.md").read_text()

        self.assertIn("# Cleytin —", soul)
        self.assertIn("You are Cleytin,", soul)

    def test_cleytin_accepts_only_mentioned_bot_alerts(self):
        source = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        argus = source.split("services.hermes-agent-oci-argus = {", 1)[1]

        self.assertIn('DISCORD_ALLOW_BOTS = "mentions";', argus)
        self.assertNotIn("discord.free_response_channels", argus)

    def test_cleytin_is_scoped_to_all_alert_channels(self):
        source = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        soul = (ROOT / "modules/hosts/discovery/argus-SOUL.md").read_text()
        argus = source.split("services.hermes-agent-oci-argus = {", 1)[1]

        self.assertIn('securityChannel = "1530261608419299428";', source)
        self.assertIn(
            'DISCORD_ALLOWED_CHANNELS = "${incidentsChannel},${deploysChannel},${securityChannel}";',
            argus,
        )
        self.assertIn('DISCORD_HOME_CHANNEL = incidentsChannel;', argus)
        self.assertIn("`#incidents`, `#deploys`, and `#security`", soul)

    def test_development_agent_identity_is_hackerman(self):
        soul = (ROOT / "modules/hosts/discovery/daedalus-SOUL.md").read_text()

        self.assertIn("# Hackerman —", soul)
        self.assertIn("You are Hackerman,", soul)

    def test_health_recipe_rejects_argus_without_runtime_credentials(self):
        justfile = (ROOT / "justfile").read_text()

        for evidence in (
            "require_env hermes-argus DISCORD_BOT_TOKEN",
            "require_env hermes-argus WEBHOOK_GRAFANA_ALERTS_SECRET",
            "require_env hermes-argus WEBHOOK_SECRET",
            "docker exec hermes-argus cat /opt/data/config.yaml",
            "grafana-alerts:",
            'printf ":: %s %s=missing',
            "http://127.0.0.1:8644/health",
            "for attempt in {1..20}; do",
            'os.environ[\\"OPENAI_API_KEY\\"]',
            "litellm=authenticated",
            "model_default=authorized",
            "for name in hermes-daedalus hermes-argus; do",
            "sudo systemctl start hermes-argus-healthcheck.service",
        ):
            self.assertIn(evidence, justfile)

    def test_cleytin_healthcheck_requires_live_discord_gateway(self):
        source = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        argus = source.split("services.hermes-agent-oci-argus = {", 1)[1]
        healthcheck = source.split(
            "systemd.services.hermes-argus-healthcheck", 1
        )[1]

        self.assertIn("enableHealthcheck = true;", argus)
        self.assertIn("/opt/data/gateway_state.json", healthcheck)
        self.assertIn('state["platforms"]["discord"]["state"] == "connected"', healthcheck)
        self.assertIn("/opt/data/state/gateway.heartbeat", healthcheck)
        self.assertIn("time.monotonic() - heartbeat[\"monotonic\"]", healthcheck)
        self.assertIn("0 <= age < 120", healthcheck)
        self.assertIn("for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do", healthcheck)

    def test_grafana_hmac_sync_uses_runtime_secret_without_plaintext_file(self):
        justfile = (ROOT / "justfile").read_text()
        recipe = justfile.split("sync-cleytin-grafana-hmac:", 1)[1].split(
            "\n\n", 1
        )[0]

        self.assertIn("/run/vault-agent/hermes-argus.env", recipe)
        self.assertIn("bao kv patch -mount=secret shared/discord @/dev/stdin", recipe)
        self.assertIn("argus_webhook_hmac", recipe)
        self.assertIn("hmac=matched", recipe)

    def test_grafana_route_canary_signs_without_secret_in_arguments(self):
        justfile = (ROOT / "justfile").read_text()
        recipe = justfile.split("test-cleytin-grafana-route:", 1)[1].split(
            "\n\n", 1
        )[0]

        self.assertIn("/run/vault-agent/hermes-argus.env", recipe)
        self.assertIn("docker exec hermes-argus python3 -c", recipe)
        self.assertIn(
            'os.environ["WEBHOOK_SECRET"] == os.environ["WEBHOOK_GRAFANA_ALERTS_SECRET"]',
            recipe,
        )
        self.assertIn("X-Request-ID", recipe)
        self.assertIn("CleytinGrafanaRouteCanary", recipe)
        self.assertIn('test "$status" = 202', recipe)

    def test_grafana_route_uses_supported_authenticated_trigger_schema(self):
        source = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        vault_agent = (ROOT / "modules/hosts/discovery/_vault-agent.nix").read_text()
        route = source.split(
            "platforms.webhook.extra.routes.grafana-alerts = {", 1
        )[1].split("};", 1)[0]

        self.assertNotIn("secret =", route)
        self.assertNotIn("hmac_secret_env", route)
        self.assertNotIn("deliver_only = true;", route)
        self.assertIn("{__raw__}", route)
        self.assertNotIn("{{ payload", route)
        self.assertIn(
            'WEBHOOK_SECRET={{ with secret \\"secret/data/shared/discord\\" }}'
            "{{ .Data.data.argus_webhook_hmac }}{{ end }}",
            vault_agent,
        )

    def test_grafana_route_delivers_firing_analysis_to_incidents(self):
        source = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        route = source.split(
            "platforms.webhook.extra.routes.grafana-alerts = {", 1
        )[1].split("};", 1)[0]

        self.assertIn('field = "payload.status";', route)
        self.assertIn('equals = "firing";', route)
        self.assertIn('deliver = "discord";', route)
        self.assertIn('chat_id = incidentsChannel;', route)


if __name__ == "__main__":
    unittest.main()
