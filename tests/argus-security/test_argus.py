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
        self.assertIn("terminal = false;", argus)

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
            "docker exec hermes-argus cat /opt/data/config.yaml",
            "grafana-alerts:",
            'printf ":: %s %s=missing',
            "http://127.0.0.1:8644/health",
            "for attempt in {1..20}; do",
            'os.environ[\\"OPENAI_API_KEY\\"]',
            "litellm=authenticated",
            "model_default=authorized",
            "for name in hermes-daedalus hermes-argus; do",
        ):
            self.assertIn(evidence, justfile)

    def test_grafana_route_uses_supported_authenticated_trigger_schema(self):
        source = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
        route = source.split(
            "platforms.webhook.extra.routes.grafana-alerts = {", 1
        )[1].split("};", 1)[0]

        self.assertIn('secret = "\\${WEBHOOK_GRAFANA_ALERTS_SECRET}";', route)
        self.assertNotIn("hmac_secret_env", route)
        self.assertNotIn("deliver_only = true;", route)


if __name__ == "__main__":
    unittest.main()
