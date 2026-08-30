import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class HermesWikiDeployContract(unittest.TestCase):
    def test_git_network_operations_retry_inside_initial_unit_start(self):
        module = (ROOT / "modules/hosts/discovery/hermes-wiki.nix").read_text()

        self.assertIn("retry_git()", module)
        self.assertIn("retry_git git clone", module)
        self.assertIn("retry_git git -C ${wikiDir} fetch", module)


if __name__ == "__main__":
    unittest.main()
