import copy
import importlib.util
import json
import pathlib
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_retire_ai_serving.py"


def load():
    spec = importlib.util.spec_from_file_location("retire_ai", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def item(container_id, name, project, image):
    return {"Id": container_id, "Image": image, "Name": name,
            "Config": {"Labels": {"com.docker.compose.project": project}}, "Mounts": []}


class RetireAiServingTests(unittest.TestCase):
    def setUp(self):
        self.module = load()
        self.items = [item(container_id, name, "ai-serving", image)
                      for name, (container_id, image) in self.module.APPROVED.items()]
        self.items += [item("b" * 64, "postgres", "infra", "sha256:" + "b" * 64),
                       item("c" * 64, "docs-search", "docs-search", "sha256:" + "c" * 64)]
        self.images = set(self.module.IMAGES)

    def test_initial_manifest_binds_full_inventory_and_exact_ids(self):
        first = self.module.plan(self.items, self.images, True)
        second = self.module.plan(list(reversed(self.items)), self.images, True)
        self.assertEqual(first, second)
        self.assertEqual(first["stage"], "remove-containers")
        self.assertEqual(first["containers"], sorted(self.module.CONTAINERS))
        self.assertRegex(first["inventory_sha256"], r"^[0-9a-f]{64}$")

    def test_resumes_images_then_path_as_separate_stages(self):
        survivors = self.items[-2:]
        remaining = set(sorted(self.images)[:3])
        manifest = self.module.plan(survivors, remaining, True)
        self.assertEqual(manifest["stage"], "remove-images")
        self.assertEqual(manifest["images"], sorted(remaining))
        self.assertFalse(manifest["remove_path"])
        path = self.module.plan(survivors, set(), True)
        self.assertEqual(path["stage"], "remove-path")
        self.assertEqual(path["images"], [])
        self.assertTrue(path["remove_path"])

    def test_all_absent_is_idempotent(self):
        manifest = self.module.plan(self.items[-2:], set(), False)
        self.assertEqual(manifest["stage"], "already-retired")
        self.assertEqual(manifest["images"], [])
        self.assertFalse(manifest["remove_path"])

    def test_halts_on_partial_wrong_shared_missing_survivor_or_bad_identity(self):
        partial = self.items[1:]
        wrong = copy.deepcopy(self.items)
        wrong[0]["Id"] = "d" * 64
        shared = self.items + [item("e" * 64, "consumer", "other", sorted(self.images)[0])]
        missing_survivor = [entry for entry in self.items if entry["Name"] != "docs-search"]
        bad = copy.deepcopy(self.items)
        bad[0]["Image"] = "sha256:UPPER"
        renamed = copy.deepcopy(self.items)
        renamed[0]["Name"] = "renamed"
        renamed[0]["Config"]["Labels"]["com.docker.compose.project"] = "other"
        for candidate in (partial, wrong, shared, missing_survivor, bad, renamed):
            with self.subTest():
                with self.assertRaises(ValueError):
                    self.module.plan(candidate, self.images, True)

    def test_full_inventory_hash_detects_foreign_drift(self):
        first = self.module.plan(self.items, self.images, True)
        drifted = self.items + [item("e" * 64, "foreign", "other", "sha256:" + "e" * 64)]
        second = self.module.plan(drifted, self.images, True)
        self.assertNotEqual(first["inventory_sha256"], second["inventory_sha256"])
        self.assertNotEqual(first["manifest_sha256"], second["manifest_sha256"])

    def test_image_inspect_requires_exact_local_image_id(self):
        expected = sorted(self.images)
        good = [mock.Mock(returncode=0, stdout=json.dumps([{"Id": image}])) for image in expected]
        with mock.patch.object(self.module.subprocess, "run", side_effect=good):
            self.assertEqual(self.module.inspect_images(), self.images)
        wrong = mock.Mock(returncode=0, stdout='[{"Id":"sha256:' + "f" * 64 + '"}]')
        with mock.patch.object(self.module.subprocess, "run", return_value=wrong):
            with self.assertRaisesRegex(ValueError, "identity drifted"):
                self.module.inspect_images()

    def test_podman_raw_image_ids_normalize_to_exact_identity(self):
        raw_items = copy.deepcopy(self.items)
        for entry in raw_items:
            entry["Image"] = entry["Image"].removeprefix("sha256:")
        manifest = self.module.plan(raw_items, self.images, True)
        self.assertEqual(manifest["stage"], "remove-containers")
        for image in self.images:
            raw = image.removeprefix("sha256:")
            self.assertEqual(self.module.canonical_image_id(raw), image)

    def test_survivor_bind_at_below_or_above_model_path_halts(self):
        survivors = self.items[-2:]
        for source in ("/fast/ai-models", "/fast/ai-models/embeddings", "/fast"):
            candidate = copy.deepcopy(survivors)
            candidate[0]["Mounts"] = [{"Type": "bind", "Source": source, "Destination": "/data"}]
            with self.subTest(source=source):
                with self.assertRaisesRegex(ValueError, "overlaps model path"):
                    self.module.plan(candidate, set(), True)

    def test_container_present_requires_all_images_and_path(self):
        for images, path_exists in ((set(sorted(self.images)[1:]), True), (self.images, False)):
            with self.assertRaises(ValueError):
                self.module.plan(self.items, images, path_exists)

    def test_no_broad_cleanup_primitive(self):
        source = SCRIPT.read_text()
        for forbidden in ("prune", "zfs destroy", "volume rm", "/fast\""):
            self.assertNotIn(forbidden, source)

    def test_remote_recipe_uses_declarative_python_interpreter(self):
        recipe = (ROOT / "justfile").read_text()
        line = next(line for line in recipe.splitlines()
                    if "_retire_ai_serving.py" in line)
        self.assertIn("kepler-collision-recovery-inventory", line)
        self.assertNotIn("'python3 -", line)


if __name__ == "__main__":
    unittest.main()
