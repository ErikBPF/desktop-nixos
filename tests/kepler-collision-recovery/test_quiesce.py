import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_quiesce.py"
FIXTURES = pathlib.Path(__file__).parent / "fixtures"


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def envelope(path, kind):
    result = json.loads(path.read_text())
    payload = result[kind]
    result[f"{kind}_sha256"] = hashlib.sha256(canonical(payload)).hexdigest()
    return result


def load_module():
    spec = importlib.util.spec_from_file_location("quiesce", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class QuiesceManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.inventory = envelope(FIXTURES / "quiesce-inventory.json", "inventory")
        self.desired = envelope(FIXTURES / "quiesce-desired.json", "desired")

    def plan(self, expected=None):
        return self.module.plan(
            self.inventory,
            self.desired,
            expected_inventory_sha256=expected or self.inventory["inventory_sha256"],
        )

    def test_names_exact_running_declared_containers_and_reverse_dependency_stacks(self):
        manifest = self.plan()["manifest"]
        self.assertEqual(manifest["stacks"], [
            {"containers": ["docs-search"], "stack": "docs-search"},
            {"containers": ["piper-openai"], "stack": "ai-serving"},
        ])
        self.assertEqual([item["command"] for item in manifest["actions"]], [
            f"just kepler-recovery-quiesce-stack docs-search {self.inventory['inventory_sha256']}",
            f"just kepler-recovery-quiesce-stack ai-serving {self.inventory['inventory_sha256']}",
        ])

    def test_manifest_is_deterministic_value_free_and_sha_bound(self):
        first = self.plan()
        second = self.plan()
        self.assertEqual(first, second)
        self.assertEqual(first["inventory_sha256"], self.inventory["inventory_sha256"])
        self.assertEqual(first["manifest_sha256"], self.module.digest(first["manifest"]))
        rendered = json.dumps(first, sort_keys=True)
        for forbidden in ("environment", "secret", "token", "password", "mounts", "image"):
            self.assertNotIn(forbidden, rendered.lower())

    def test_ignores_stopped_restate_retirement_and_stopped_declared_containers(self):
        self.inventory["inventory"]["containers"][0]["state"] = "exited"
        self.inventory["inventory_sha256"] = self.module.digest(self.inventory["inventory"])
        manifest = self.plan()["manifest"]
        self.assertNotIn("protected_containers", manifest)
        self.assertEqual(manifest["stacks"], [{"containers": ["docs-search"], "stack": "docs-search"}])

    def test_rejects_unknown_foreign_unlabeled_and_declared_service_mismatch(self):
        mutations = (
            lambda item: item.update({"name": "unknown"}),
            lambda item: item["labels"].update({"com.docker.compose.project": "foreign"}),
            lambda item: item.update({"labels": {}}),
            lambda item: item["labels"].update({"com.docker.compose.service": "other"}),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                original = copy.deepcopy(self.inventory)
                mutation(self.inventory["inventory"]["containers"][0])
                self.inventory["inventory_sha256"] = self.module.digest(self.inventory["inventory"])
                with self.assertRaises(self.module.QuiesceHalt):
                    self.plan()
                self.inventory = original

    def test_rejects_running_retired_container(self):
        item = self.inventory["inventory"]["containers"][0]
        item.update({"name": "gitlab"})
        item["labels"] = {
            "com.docker.compose.project": "gitlab",
            "com.docker.compose.service": "gitlab",
        }
        self.inventory["inventory_sha256"] = self.module.digest(self.inventory["inventory"])
        with self.assertRaisesRegex(self.module.QuiesceHalt, "retired container is running"):
            self.plan()

    def test_rejects_running_restate_as_retired(self):
        item = next(item for item in self.inventory["inventory"]["containers"] if item["name"] == "restate")
        item["state"] = "running"
        self.inventory["inventory_sha256"] = self.module.digest(self.inventory["inventory"])
        with self.assertRaisesRegex(self.module.QuiesceHalt, "retired container is running"):
            self.plan()

    def test_rejects_inventory_drift_and_invalid_envelope(self):
        with self.assertRaisesRegex(self.module.QuiesceHalt, "inventory drift"):
            self.plan(expected="f" * 64)
        self.inventory["inventory_sha256"] = "0" * 64
        with self.assertRaisesRegex(self.module.QuiesceHalt, "SHA-256 mismatch"):
            self.plan(expected="0" * 64)

    def test_records_downtime_abort_rollback_and_dry_run_only_contract(self):
        manifest = self.plan()["manifest"]
        self.assertEqual(manifest["mode"], "dry-run-only")
        self.assertEqual(manifest["execution_supported"], False)
        self.assertEqual(manifest["abort_boundary"], "before-first-stop-on-any-drift-or-failed-precondition")
        self.assertEqual(manifest["rollback"], [
            "just kick-stack kepler ai-serving",
            "just kick-stack kepler docs-search",
        ])
        self.assertEqual(manifest["downtime"], "until-fresh-inventory-and-approved-K1-continuation")

    def test_no_execute_api_or_unsafe_command(self):
        self.assertFalse(hasattr(self.module, "execute"))
        commands = "\n".join(item["command"] for item in self.plan()["manifest"]["actions"])
        for forbidden in ("ssh", "rm ", "prune", "destroy", "podman", "docker"):
            self.assertNotIn(forbidden, commands)


if __name__ == "__main__":
    unittest.main()
