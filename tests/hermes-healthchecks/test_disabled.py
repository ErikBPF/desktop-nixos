import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class HermesHealthcheckContract(unittest.TestCase):
    def test_discovery_disables_all_three_oci_healthchecks(self):
        primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
        agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

        self.assertIn("services.hermes-agent-oci = {", primary)
        self.assertEqual(primary.count("enableHealthcheck = false;"), 1)
        self.assertIn("services.hermes-agent-oci-daedalus = {", agents)
        self.assertIn("services.hermes-agent-oci-argus = {", agents)
        self.assertEqual(agents.count("enableHealthcheck = false;"), 2)


if __name__ == "__main__":
    unittest.main()
