import hashlib
import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_retirement_paths_remote.py"


def load_module():
    spec = importlib.util.spec_from_file_location("retirement_paths", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RetirementPathEvidenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def populate(self, root):
        for path in self.module.ALLOWLIST:
            candidate = root / path.removeprefix("/")
            candidate.mkdir(parents=True)
        model = root / "fast/ai-models/f5-tts/model.safetensors"
        model.write_bytes(b"not emitted")

    def test_exact_allowlist_and_value_free_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.populate(root)
            first = self.module.collect(root)
            second = self.module.collect(root)
        self.assertEqual(first, second)
        evidence = first["evidence"]
        self.assertEqual([item["path"] for item in evidence], list(self.module.ALLOWLIST))
        self.assertTrue(all(set(item) == {
            "byte_count", "device", "existence", "inode", "path", "type"
        } for item in evidence))
        self.assertTrue(all(item["existence"] is True for item in evidence))
        self.assertTrue(all(item["type"] == "directory" for item in evidence))
        rendered = json.dumps(first, sort_keys=True)
        self.assertNotIn("model.safetensors", rendered)
        self.assertNotIn("not emitted", rendered)

    def test_envelope_is_deterministic_and_hash_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.populate(root)
            result = self.module.collect(root)
        self.assertEqual(result["schema"], "kepler-retirement-path-evidence-envelope-v1")
        self.assertEqual(result["status"], "verified")
        self.assertEqual(result["evidence_sha256"], hashlib.sha256(
            self.module.canonical(result["evidence"])
        ).hexdigest())

    def test_missing_path_records_absence_without_listing(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.module.collect(pathlib.Path(directory))
        for item in result["evidence"]:
            self.assertEqual(item, {
                "byte_count": None,
                "device": None,
                "existence": False,
                "inode": None,
                "path": item["path"],
                "type": None,
            })

    def test_rejects_leaf_and_intermediate_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            outside = root / "outside"
            outside.mkdir()
            leaf = root / "bulk/git"
            leaf.parent.mkdir(parents=True)
            leaf.symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(self.module.PathEvidenceHalt, "symlink"):
                self.module.collect(root)
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            outside = root / "outside"
            outside.mkdir()
            (root / "fast").symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(self.module.PathEvidenceHalt, "symlink"):
                self.module.collect(root)

    def test_rejects_realpath_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            candidate = root / "bulk/git"
            candidate.parent.mkdir(parents=True)
            candidate.symlink_to(pathlib.Path(directory).parent, target_is_directory=True)
            with self.assertRaises(self.module.PathEvidenceHalt):
                self.module.collect(root)

    def test_remote_cli_rejects_all_arguments(self):
        completed = subprocess.run(
            ["python3", str(SCRIPT), "/tmp"], capture_output=True, text=True,
            env={**os.environ, "PYTHONWARNINGS": "error"},
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("accepts no arguments", completed.stderr)
        self.assertEqual(completed.stdout, "")


if __name__ == "__main__":
    unittest.main()
