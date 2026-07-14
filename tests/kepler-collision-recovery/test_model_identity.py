import hashlib
import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_model_identity_remote.py"


class ModelIdentityTest(unittest.TestCase):
    def run_identity(self, root, artifacts):
        request = {
            "artifacts": [
                {"artifact": name, "identity_path": str(root / relative), "kind": kind}
                for name, relative, kind in artifacts
            ],
            "schema": "kepler-k1-model-paths-v1",
        }
        return subprocess.run(
            ["python3", str(SCRIPT), "--fixture-root", str(root)],
            input=json.dumps(request), capture_output=True, text=True,
        )

    def test_deterministic_value_free_hash_envelope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            model = root / "model"
            model.mkdir()
            (model / "weights.bin").write_bytes(b"secret model bytes")
            (model / "config.json").write_bytes(b"{}")
            first = self.run_identity(root, [("model-a", "model", "directory")])
            second = self.run_identity(root, [("model-a", "model", "directory")])
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        envelope = json.loads(first.stdout)
        self.assertEqual(set(envelope), {"evidence", "evidence_sha256", "schema"})
        self.assertEqual(envelope["schema"], "kepler-k1-model-identities-envelope-v1")
        identity = envelope["evidence"]["artifacts"][0]
        self.assertEqual(identity["algorithm"], "kepler-tree-sha256-v1")
        self.assertEqual(identity["byte_count"], len(b"secret model bytes{}"))
        self.assertEqual(identity["entry_count"], 3)
        self.assertRegex(identity["sha256"], r"^[0-9a-f]{64}$")
        self.assertNotIn("weights.bin", first.stdout)
        self.assertNotIn("config.json", first.stdout)
        self.assertNotIn("secret model bytes", first.stdout)
        canonical = json.dumps(envelope["evidence"], sort_keys=True, separators=(",", ":")).encode()
        self.assertEqual(envelope["evidence_sha256"], hashlib.sha256(canonical).hexdigest())

    def test_hash_binds_names_contents_and_symlink_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            model = root / "model"
            blobs = root / "blobs"
            model.mkdir()
            blobs.mkdir()
            target = blobs / "one"
            target.write_bytes(b"one")
            link = model / "weights"
            link.symlink_to(target)
            first = self.run_identity(root, [("model-a", "model", "directory")])
            target.write_bytes(b"two")
            second = self.run_identity(root, [("model-a", "model", "directory")])
            link.unlink()
            link.symlink_to(blobs / "missing")
            failed = self.run_identity(root, [("model-a", "model", "directory")])
        self.assertNotEqual(json.loads(first.stdout)["evidence_sha256"], json.loads(second.stdout)["evidence_sha256"])
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(json.loads(failed.stderr)["diagnostics"], [{"artifact": "model-a", "reason": "unsafe-path"}])
        self.assertNotIn("missing", failed.stderr)

    def test_rejects_escape_and_duplicate_artifact_without_leaking_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            outside = pathlib.Path(directory).parent / "outside-model-fixture"
            outside.write_bytes(b"outside")
            try:
                (root / "escape").symlink_to(outside)
                failed = self.run_identity(root, [("model-a", "escape", "file")])
                duplicate = self.run_identity(root, [
                    ("model-a", "escape", "file"), ("model-a", "escape", "file"),
                ])
            finally:
                outside.unlink()
        self.assertEqual(json.loads(failed.stderr)["diagnostics"], [{"artifact": "model-a", "reason": "unsafe-path"}])
        self.assertEqual(json.loads(duplicate.stderr)["diagnostics"], [{"artifact": "model-a", "reason": "duplicate-artifact"}])
        self.assertNotIn(str(outside), failed.stderr + duplicate.stderr)

    def test_malformed_input_halts_without_traceback(self):
        completed = subprocess.run(
            ["python3", str(SCRIPT)], input='{"schema":"kepler-k1-model-paths-v1","artifacts":[7]}',
            capture_output=True, text=True,
        )
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(json.loads(completed.stderr)["diagnostics"], [
            {"artifact": "model-inventory", "reason": "invalid-schema"},
        ])
        self.assertNotIn("Traceback", completed.stderr)


if __name__ == "__main__":
    unittest.main()
