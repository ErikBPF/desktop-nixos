#!/usr/bin/env python3
"""Boot-order contract for Discovery OpenBao startup."""

from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
VAULT = (ROOT / "modules/hosts/discovery/vault.nix").read_text()
AGENT = (ROOT / "modules/hosts/discovery/_vault-agent.nix").read_text()
HARBOR = (ROOT / "modules/hosts/discovery/harbor.nix").read_text()
WIKI = (ROOT / "modules/hosts/discovery/hermes-wiki.nix").read_text()
CONTAINERS = (ROOT / "modules/hosts/discovery/containers.nix").read_text()


def between(text: str, start: str, end: str) -> str:
    begin = text.index(start)
    return text[begin:text.index(end, begin)]


class OpenBaoBootOrderTest(unittest.TestCase):
    def test_unseal_is_not_pulled_by_boot_target(self):
        block = between(
            VAULT,
            "systemd.services.openbao-unseal = {",
            "systemd.timers.openbao-unseal = {",
        )
        self.assertNotIn('wantedBy = ["multi-user.target"]', block)
        self.assertIn('TimeoutStartSec = "6min"', block)
        self.assertIn('wants = ["openbao.service"]', block)

    def test_agent_does_not_order_after_unseal(self):
        self.assertNotIn('after = ["openbao-unseal.service"]', AGENT)
        self.assertIn('wants = ["openbao-unseal.service"]', AGENT)
        self.assertIn("startLimitIntervalSec = 0;", AGENT)

    def test_network_is_owned_before_openbao(self):
        block = between(
            VAULT,
            "systemd.services.openbao-network = {",
            "systemd.services.openbao = {",
        )
        self.assertIn('before = ["openbao.service"]', block)
        self.assertIn("docker network create", block)
        self.assertIn("ip link add name", block)
        self.assertIn("openbao-proxy", block)
        self.assertIn("br-openbao", block)
        self.assertIn('TimeoutStartSec = "2min"', block)
        self.assertIn('Restart = "on-failure"', block)
        self.assertIn("startLimitIntervalSec = 0;", block)
        self.assertIn('No such network', block)
        self.assertIn("exit 1", block)

    def test_openbao_waits_for_network(self):
        block = between(
            VAULT,
            "systemd.services.openbao = {",
            "services.logrotate.settings.openbao-audit",
        )
        self.assertIn('"openbao-network.service"', block)
        self.assertIn(
            'after = ["tailscaled.service" "network-online.target" "openbao-network.service"]',
            block,
        )

    def test_remaining_boot_gates_are_bounded(self):
        self.assertIn('TimeoutStartSec = "5min"', HARBOR)
        self.assertIn('TimeoutStartSec = "3min"', WIKI)
        self.assertIn('TimeoutStartSec = "3min"', CONTAINERS)


if __name__ == "__main__":
    unittest.main()
