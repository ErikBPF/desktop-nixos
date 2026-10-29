"""Render the deferred cache module with synthetic fleet identities."""

import json
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
WRITERS = {"endeavour": "127.0.0.2", "laptop": "127.0.0.3", "kepler": "127.0.0.4"}
LEGACY_LAPTOP = "100.74.137.124"  # Accepted peer retained in the IaC tailnet ACL.


def cache_config(module=None, hosts=None):
    module = Path(module or ROOT / "modules/services/sccache.nix").resolve()
    if hosts is None:
        hosts = {name: {"tailscaleIp": address} for name, address in WRITERS.items()}
        hosts["orion"] = {"tailscaleIp": "127.0.0.5"}
    # Only the leaf's enable/description helpers are needed here. Effective
    # NixOS option merging and the host closure have a separate native gate.
    expression = """
      let
        fleet = builtins.fromJSON %s;
        module = import (builtins.toPath %s) { config = { inherit fleet; }; };
        leaf = module.flake.modules.nixos.sccache-cache {
          config.services.sccacheCache.enable = true;
          lib.mkIf = condition: value: if condition then value else {};
          lib.mkEnableOption = description: { inherit description; };
        };
      in {
        extra = leaf.config.services.nginx.virtualHosts.sccache-cache.locations."/".extraConfig;
        listen = leaf.config.services.nginx.virtualHosts.sccache-cache.listen;
        ports = leaf.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
      }
    """ % (json.dumps(json.dumps({"hosts": hosts})), json.dumps(str(module)))
    result = subprocess.run(
        ["nix-instantiate", "--eval", "--strict", "--json", "--expr", expression],
        check=False, capture_output=True, text=True,
    )
    if result.returncode:
        raise AssertionError("cache module evaluation failed: " + result.stderr)
    return json.loads(result.stdout)


class CacheWriterContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = cache_config()

    def test_only_accepted_remote_writers_can_mutate(self):
        block = re.search(r"limit_except\s+GET\s*\{([^}]*)\}", self.config["extra"])
        self.assertIsNotNone(block, "cache mutations have no server-side writer boundary")
        allowed = set(re.findall(r"allow\s+([^;]+);", block[1]))
        self.assertEqual(allowed, {WRITERS["endeavour"], WRITERS["kepler"],
                                  LEGACY_LAPTOP, "127.0.0.1", "::1"})
        self.assertRegex(block[1], r"deny\s+all;")
        self.assertTrue(block[1].strip().endswith("deny all;"))

    def test_read_and_existing_dav_methods_remain(self):
        self.assertIn("dav_methods PUT DELETE MKCOL COPY MOVE;", self.config["extra"])
        self.assertNotIn("auth_basic", self.config["extra"])
        self.assertEqual(self.config["listen"], [{"addr": "0.0.0.0", "port": 4321}])
        self.assertEqual(self.config["ports"], [4321])

    def test_current_fleet_resolves_accepted_legacy_writer(self):
        hosts = json.loads((ROOT / "fleet.json").read_text())["hosts"]
        rendered = cache_config(hosts=hosts)["extra"]
        allowed = set(re.findall(r"allow\s+([^;]+);", rendered))
        self.assertEqual(allowed, {hosts["endeavour"]["tailscaleIp"],
                                  hosts["kepler"]["tailscaleIp"],
                                  LEGACY_LAPTOP, "127.0.0.1", "::1"})


if __name__ == "__main__":
    unittest.main()
