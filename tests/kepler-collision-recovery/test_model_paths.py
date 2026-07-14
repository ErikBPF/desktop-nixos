import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_model_paths_remote.py"


def load_module():
    spec = importlib.util.spec_from_file_location("model_paths", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ModelPathDiscoveryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def populate(self, root):
        directories = (
            "embeddings/hub/models--BAAI--bge-m3",
            "embeddings/hub/models--BAAI--bge-reranker-v2-m3",
            "refs", "piper",
            "whisper/models--Systran--faster-whisper-large-v3-turbo",
            "f5-tts/models--firstpixel--F5-TTS-pt-br/snapshots/abc123/pt-br",
        )
        for relative in directories:
            (root / relative).mkdir(parents=True)
        (root / "gemma4").mkdir()
        (root / "gemma4/gemma-4-E2B-it-Q8_0.gguf").write_bytes(b"fixture")
        (root / "f5-tts/models--firstpixel--F5-TTS-pt-br/snapshots/abc123/pt-br/model_last.safetensors").write_bytes(b"fixture")

    def test_discovers_exact_value_free_artifact_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.populate(root)
            first = self.module.discover(root)
            second = self.module.discover(root)
        self.assertEqual(first, second)
        self.assertEqual(set(first), {"artifacts", "schema"})
        self.assertEqual(first["schema"], "kepler-k1-model-paths-v1")
        self.assertEqual(
            [item["artifact"] for item in first["artifacts"]],
            sorted({*self.module.ARTIFACTS, "f5-tts-checkpoint", "whisper-model"}),
        )
        self.assertTrue(all(set(item) == {"artifact", "identity_path", "kind", "status"} for item in first["artifacts"]))
        by_name = {item["artifact"]: item for item in first["artifacts"]}
        self.assertEqual(by_name["whisper-model"]["identity_path"], "/fast/ai-models/whisper/models--Systran--faster-whisper-large-v3-turbo")
        self.assertRegex(by_name["f5-tts-checkpoint"]["identity_path"], r"/snapshots/abc123/pt-br/model_last\.safetensors$")
        rendered = json.dumps(first, sort_keys=True)
        self.assertNotIn(directory, rendered)
        self.assertNotIn("fixture", rendered)

    def test_whisper_and_f5_ambiguity_halt_without_leaking_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.populate(root)
            (root / "whisper/large-v3-turbo").mkdir()
            with self.assertRaisesRegex(self.module.DiscoveryHalt, "whisper-model identity path is ambiguous"):
                self.module.discover(root)
            (root / "whisper/large-v3-turbo").rmdir()
            extra = root / "f5-tts/models--firstpixel--F5-TTS-pt-br/snapshots/def456/pt-br"
            extra.mkdir(parents=True)
            (extra / "model_last.safetensors").write_bytes(b"other")
            with self.assertRaisesRegex(self.module.DiscoveryHalt, "f5-tts-checkpoint identity path is ambiguous"):
                self.module.discover(root)

    def test_rejects_escape_broken_symlink_and_special_file(self):
        cases = ("escape", "broken", "special")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                self.populate(root)
                target = root / "gemma4/gemma-4-E2B-it-Q8_0.gguf"
                target.unlink()
                if case == "escape":
                    target.symlink_to("/etc/passwd")
                elif case == "broken":
                    target.symlink_to("missing")
                else:
                    os.mkfifo(target)
                with self.assertRaisesRegex(self.module.DiscoveryHalt, "artifact path validation failed"):
                    self.module.discover(root)

    def test_rejects_cross_device_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.populate(root)
            target = root / "gemma4/gemma-4-E2B-it-Q8_0.gguf"
            real_lstat = pathlib.Path.lstat

            def lstat(path):
                metadata = real_lstat(path)
                if path == target:
                    return os.stat_result((*metadata[:2], metadata.st_dev + 1, *metadata[3:]))
                return metadata

            with mock.patch.object(pathlib.Path, "lstat", lstat):
                with self.assertRaisesRegex(self.module.DiscoveryHalt, "artifact path validation failed"):
                    self.module.discover(root)

    def test_cli_fixture_mode_is_canonical_and_error_is_value_free(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.populate(root)
            completed = subprocess.run(
                ["python3", str(SCRIPT), "--fixture-root", str(root)],
                check=True, capture_output=True, text=True,
            )
            self.assertEqual(completed.stdout, json.dumps(json.loads(completed.stdout), sort_keys=True, separators=(",", ":")) + "\n")
            (root / "refs").rmdir()
            failed = subprocess.run(
                ["python3", str(SCRIPT), "--fixture-root", str(root)],
                capture_output=True, text=True,
            )
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(failed.stderr, "model-path discovery halted: required artifact path unavailable\n")
        self.assertNotIn(directory, failed.stderr)


if __name__ == "__main__":
    unittest.main()
