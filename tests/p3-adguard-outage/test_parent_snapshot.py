import copy
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CLIENT = ROOT / "scripts/p3-adguard-outage-client.sh"


def normalize_address(value):
    return [{
        "ifname": item["ifname"], "address": item["address"], "mtu": item["mtu"],
        "flags": sorted(item["flags"]),
        "addr_info": sorted(
            ({key: address[key] for key in ("family", "local", "prefixlen", "scope", "label")}
             for address in item["addr_info"]),
            key=lambda address: tuple(address[key] for key in ("family", "local", "prefixlen", "scope", "label")),
        ),
    } for item in value]


def normalize_routes(value):
    volatile = {"expires", "cache", "used", "lastuse"}
    routes = [{key: copy.deepcopy(item[key]) for key in item if key not in volatile} for item in value]
    for route in routes:
        if "nexthops" in route:
            route["nexthops"].sort(key=lambda hop: (hop.get("dev"), hop.get("gateway"), hop.get("weight")))
    return sorted(routes, key=lambda route: (route.get("table", "main"), route.get("dst", "default"), route.get("gateway", ""), route.get("prefsrc", ""), route.get("protocol", "")))


class ParentSnapshot(unittest.TestCase):
    def test_lifetime_and_route_expiry_changes_are_ignored(self):
        address = [{"ifname": "eno1", "address": "00:11:22:33:44:55", "mtu": 1500, "flags": ["UP", "LOWER_UP"], "addr_info": [{"family": "inet", "local": "192.168.10.125", "prefixlen": 24, "scope": "global", "label": "eno1", "valid_life_time": 100, "preferred_life_time": 50}]}]
        route = [{"dst": "default", "gateway": "192.168.10.1", "dev": "eno1", "protocol": "dhcp", "expires": 100, "cache": ["x"], "used": 4, "lastuse": 3}]
        changed_address = copy.deepcopy(address); changed_address[0]["addr_info"][0]["valid_life_time"] = 99
        changed_route = copy.deepcopy(route); changed_route[0].update(expires=99, used=5, lastuse=4)
        self.assertEqual(normalize_address(address), normalize_address(changed_address))
        self.assertEqual(normalize_routes(route), normalize_routes(changed_route))

    def test_stable_address_and_route_drift_is_rejected(self):
        address = [{"ifname": "eno1", "address": "00:11:22:33:44:55", "mtu": 1500, "flags": ["UP"], "addr_info": [{"family": "inet", "local": "192.168.10.125", "prefixlen": 24, "scope": "global", "label": "eno1"}]}]
        changed_address = copy.deepcopy(address); changed_address[0]["addr_info"][0]["prefixlen"] = 25
        route = [{"dst": "default", "gateway": "192.168.10.1", "dev": "eno1", "protocol": "dhcp"}]
        changed_route = copy.deepcopy(route); changed_route[0]["gateway"] = "192.168.10.254"
        self.assertNotEqual(normalize_address(address), normalize_address(changed_address))
        self.assertNotEqual(normalize_routes(route), normalize_routes(changed_route))

    def test_client_uses_the_semantic_projection(self):
        source = CLIENT.read_text()
        self.assertIn("{ifname,address,mtu,flags:", source)
        self.assertIn("{family,local,prefixlen,scope,label}", source)
        self.assertIn("del(.expires,.cache,.used,.lastuse)", source)


if __name__ == "__main__":
    unittest.main()
