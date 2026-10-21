"""Discovery's OCI healthcheck posture is explicit per agent.

The periodic sidecar probe is the only readiness source these containers have
(the OCI module cannot declare a Docker HEALTHCHECK), so whether it runs is a
deliberate per-agent choice, not uniform.
"""

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class HermesHealthcheckContract(unittest.TestCase):
    def test_discovery_declares_each_agent_healthcheck_explicitly(self):
        primary = (ROOT / "modules/hosts/discovery/hermes-oci.nix").read_text()
        agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()

        self.assertIn("services.hermes-agent-oci = {", primary)
        self.assertIn("enableHealthcheck = true;", primary)

        self.assertIn("services.hermes-agent-oci-daedalus = {", agents)
        self.assertIn("services.hermes-agent-oci-argus = {", agents)
        self.assertEqual(agents.count("enableHealthcheck = true;"), 1)
        self.assertEqual(agents.count("enableHealthcheck = false;"), 1)


if __name__ == "__main__":
    unittest.main()
