#!/usr/bin/env python3
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class ArgusSecurityContract(unittest.TestCase):
    def test_argus_disables_terminal_tools(self):
        source = (
            ROOT / "modules/hosts/discovery/hermes-agents.nix"
        ).read_text()
        argus = source.split(
            "services.hermes-agent-oci-argus = {", 1
        )[1]
        self.assertIn("terminal = false;", argus)


if __name__ == "__main__":
    unittest.main()
