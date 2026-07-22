#!/usr/bin/env python3
"""DS8 ha-harness SecretSpec runtime wiring contract."""

from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
COMPOSE = ROOT / "modules/hosts/discovery/compose.nix"


class HaHarnessCutoverTest(unittest.TestCase):
    def test_discovery_enables_ha_harness_profile_and_targeted_health(self):
        source = COMPOSE.read_text()
        self.assertIn('secretSpecRuntimeProfiles.ha-harness = "ha-harness";', source)
        self.assertIn('secretSpecRuntimeHealthContainers.ha-harness = "ha-harness";', source)


if __name__ == "__main__":
    unittest.main()
