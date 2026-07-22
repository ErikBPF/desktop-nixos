#!/usr/bin/env python3
"""DS8 tools SecretSpec runtime wiring contract."""

from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
ORCHESTRATION = ROOT / "modules/server/orchestration.nix"
COMPOSE = ROOT / "modules/hosts/discovery/compose.nix"


class ToolsCutoverTest(unittest.TestCase):
    def test_discovery_enables_only_tools_runtime_profile(self):
        source = COMPOSE.read_text()
        self.assertIn('secretSpecRuntimeProfiles.tools = "tools";', source)
        self.assertIn('secretSpecRuntimeHealthContainers.tools = "searxng";', source)

    def test_runtime_wrapper_is_fail_closed_and_removes_direct_provider_flag(self):
        source = ORCHESTRATION.read_text()
        self.assertIn("secretSpecRuntimeProfiles", source)
        self.assertIn("${pkgs.secretspec}/bin/secretspec run", source)
        self.assertIn("--reason discovery-${name}-production-runtime", source)
        self.assertIn("lib.optionals (secretSpecProfile == null) vaultBasenames", source)
        self.assertIn("systemctl is-active vault-agent.service", source)
        self.assertIn("secretspec-runtime-projection", source)
        self.assertNotIn("secretSpecWait", source)
        self.assertIn("up -d --remove-orphans", source)
        self.assertIn("ExecStartPost = lib.optional", source)
        self.assertIn("/bin/docker inspect --format '{{.State.Health.Status}}'", source)
        self.assertIn('health_container="${secretSpecHealthContainer}"', source)


if __name__ == "__main__":
    unittest.main()
