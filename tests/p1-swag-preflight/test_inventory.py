import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "modules/hosts/discovery/_stateful-swag-inventory.py"
RAW = pathlib.Path(__file__).parent / "fixtures/raw-observations.json"
EXPECTED = pathlib.Path(__file__).parent / "fixtures/inventory.json"


def load_collector():
    spec = importlib.util.spec_from_file_location("swag_inventory", COLLECTOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SwagInventoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def test_raw_observations_normalize_to_exact_inventory(self):
        raw = json.loads(RAW.read_text())
        self.assertEqual(self.collector.normalize(raw), json.loads(EXPECTED.read_text()))

    def test_capture_surface_is_read_only_and_value_free(self):
        source = COLLECTOR.read_text().lower()
        for token in ("docker stop", "docker rm", "compose up", "volume rm", "prune", "rm -r", "environment", "secret_value", "token_value"):
            self.assertNotIn(token, source)
        for required in ("docker", "inspect", "git", "rev-parse", "openssl", "sha256"):
            self.assertIn(required, source)


if __name__ == "__main__":
    unittest.main()
