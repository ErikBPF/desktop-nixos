"""Check Apollo's evaluated uplink configuration without activation.

Run: python3 -m unittest discover -s tests/apollo-nic-recovery
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
OPTIONS = """c: {
  link = c.systemd.network.links."10-apollo-lan" or null;
  dhcpInterfaces = builtins.filter
    (name: c.networking.interfaces.${name}.useDHCP == true)
    (builtins.attrNames c.networking.interfaces);
  natEnabled = c.networking.nat.enable;
  natInterface = c.networking.nat.externalInterface;
  networkManager = c.networking.networkmanager.enable;
  networkd = c.networking.useNetworkd;
  stage1Enabled = c.boot.initrd.systemd.enable;
  stage1Link = c.boot.initrd.systemd.network.units."10-apollo-lan.link".text or null;
  stage2Link = c.systemd.network.units."10-apollo-lan.link".text or null;
}"""


class ApolloUplinkOptions(unittest.TestCase):
    def test_permanent_mac_binds_one_dhcp_and_nat_uplink(self):
        options = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", ".#nixosConfigurations.apollo.config",
             "--apply", OPTIONS], cwd=ROOT, text=True,
        ))
        mac = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", ".#fleet.hosts.apollo.mac"],
            cwd=ROOT, text=True,
        ))
        with self.subTest(binding="permanent MAC and stable name"):
            self.assertIsNotNone(options["link"])
            self.assertTrue(options["link"]["enable"])
            self.assertEqual(options["link"]["matchConfig"]["PermanentMACAddress"], mac)
            self.assertEqual(options["link"]["linkConfig"]["Name"], "lan0")
            self.assertEqual(options["link"]["linkConfig"]["NamePolicy"], "")
        with self.subTest(binding="DHCP and NAT"):
            self.assertEqual(options["dhcpInterfaces"], ["lan0"])
            self.assertTrue(options["natEnabled"])
            self.assertEqual(options["natInterface"], "lan0")
        with self.subTest(binding="network ownership"):
            self.assertTrue(options["networkd"])
            self.assertFalse(options["networkManager"])
        with self.subTest(binding="rendered early boot and system link"):
            self.assertIn(f"[Match]\nPermanentMACAddress={mac}\n", options["stage2Link"])
            self.assertIn("[Link]\nName=lan0\nNamePolicy=\n", options["stage2Link"])
            self.assertTrue(options["stage1Enabled"])
            self.assertEqual(options["stage1Link"], options["stage2Link"])


if __name__ == "__main__":
    unittest.main()
