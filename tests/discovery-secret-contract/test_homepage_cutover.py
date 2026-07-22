#!/usr/bin/env python3
"""Homepage SecretSpec runtime wiring contract."""

from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
COMPOSE = ROOT / "modules/hosts/discovery/compose.nix"


class HomepageCutoverTest(unittest.TestCase):
    def test_homepage_uses_atomic_projection_and_targeted_health(self):
        source = COMPOSE.read_text()
        self.assertIn('secretSpecRuntimeProfiles.homepage = "homepage";', source)
        self.assertIn(
            'secretSpecRuntimeSourceConfigNames.homepage = ["GRAFANA_ADMIN_USER"];',
            source,
        )
        self.assertIn('secretSpecRuntimeHealthContainers.homepage = "homepage";', source)
        self.assertIn('homepage = ["shared-arr" "shared-grafana"];', source)


if __name__ == "__main__":
    unittest.main()
