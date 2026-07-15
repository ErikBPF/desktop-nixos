import copy
import hashlib
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
CLIENT = ROOT / "scripts/p3-adguard-outage-client.sh"
OBSERVE = ROOT / "scripts/p3-adguard-outage-observe.sh"
DRILL = ROOT / "scripts/p3-adguard-outage-drill.sh"


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def ra_contract():
    return {
        "router": "fe80::1",
        "default_route": {
            "dst": "default",
            "gateway": "fe80::1",
            "dev": "p3d1234",
            "protocol": "ra",
        },
        "prefix": "2001:db8:10::/64",
        "rdnss": "2001:db8:10::53",
        "router_lifetime": "positive",
        "rdnss_lifetime": "positive",
    }


class RdnssContract(unittest.TestCase):
    def test_exact_normalized_ra_contract_accepts_only_one_positive_rdnss(self):
        expected = ra_contract()
        self.assertEqual(set(expected), {
            "router", "default_route", "prefix", "rdnss",
            "router_lifetime", "rdnss_lifetime",
        })
        self.assertEqual(expected["default_route"]["gateway"], expected["router"])
        self.assertEqual(expected["default_route"]["dst"], "default")
        self.assertEqual(expected["default_route"]["protocol"], "ra")
        self.assertEqual(expected["router_lifetime"], "positive")
        self.assertEqual(expected["rdnss_lifetime"], "positive")
        self.assertIsInstance(expected["rdnss"], str)

    def test_stable_ra_rdnss_and_order_drift_changes_inventory(self):
        base = {
            "ipv6": ra_contract(),
            "resolvers": {
                "nameservers": ["2001:db8:10::53", "192.168.10.210", "192.168.10.230"],
                "options": ["timeout:2", "attempts:1"],
            },
        }
        mutations = []
        changed = copy.deepcopy(base); changed["ipv6"]["router"] = "fe80::2"; mutations.append(changed)
        changed = copy.deepcopy(base); changed["ipv6"]["default_route"]["gateway"] = "fe80::2"; mutations.append(changed)
        changed = copy.deepcopy(base); changed["ipv6"]["prefix"] = "2001:db8:11::/64"; mutations.append(changed)
        changed = copy.deepcopy(base); changed["ipv6"]["rdnss"] = "2001:db8:10::54"; mutations.append(changed)
        changed = copy.deepcopy(base); changed["ipv6"]["rdnss_lifetime"] = "zero"; mutations.append(changed)
        changed = copy.deepcopy(base); changed["resolvers"]["nameservers"].reverse(); mutations.append(changed)
        changed = copy.deepcopy(base); changed["resolvers"]["options"] = ["attempts:1", "timeout:2"]; mutations.append(changed)
        for changed in mutations:
            self.assertNotEqual(canonical_hash(base), canonical_hash(changed))

    def test_nonce_and_query_results_are_hash_bound_without_raw_nonce(self):
        query_results = [
            {"transport": "udp", "resolver": "rdnss", "kind": "fleet-a", "status": "NOERROR", "answers": 1},
            {"transport": "tcp", "resolver": "rdnss", "kind": "external-aaaa", "status": "NOERROR", "answers": 1},
        ]
        first_nonce = canonical_hash({"nonce": "fixture-one"})
        second_nonce = canonical_hash({"nonce": "fixture-two"})
        evidence = {"classifications_sha256": canonical_hash(["fleet-a", "external-positive"]),
            "nonce_sha256": first_nonce, "qnames_sha256": canonical_hash(["a.example", "b.example"]),
            "results_sha256": canonical_hash(query_results)}
        self.assertEqual(len(evidence["nonce_sha256"]), 64)
        self.assertEqual(len(evidence["results_sha256"]), 64)
        self.assertEqual(len(evidence["qnames_sha256"]), 64)
        self.assertEqual(len(evidence["classifications_sha256"]), 64)
        self.assertNotEqual(first_nonce, second_nonce)
        changed = copy.deepcopy(query_results); changed[0]["answers"] = 0
        self.assertNotEqual(evidence["results_sha256"], canonical_hash(changed))
        self.assertNotIn("fixture-one", json.dumps(evidence))

    def test_scripts_expose_rdnss_prepare_and_hash_contract(self):
        client = CLIENT.read_text()
        observer = OBSERVE.read_text()
        drill = DRILL.read_text()
        self.assertIn("RDISC6", client.upper())
        self.assertIn("nonce_sha256", observer)
        self.assertIn("results_sha256", observer)
        self.assertIn("probe_contract", observer)
        self.assertIn("probe_evidence", drill)
        self.assertIn('[ "${#routers[@]}" -ne 1 ]', observer)
        self.assertIn('[ "${#advertised_dns[@]}" -ne 1 ]', observer)
        self.assertIn('[ "${router_lifetimes[0]}" -le 0 ]', observer)
        self.assertIn('[ "${dns_lifetimes[0]}" -le 0 ]', observer)
        self.assertIn('del(.probe_evidence)', drill)


if __name__ == "__main__":
    unittest.main()
