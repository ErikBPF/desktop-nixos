import copy
import importlib.util
import json
import pathlib
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_desired.py"
SERVARR = ROOT / "references/repos/servarr/machines/kepler"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/k1-desired.json"


def load_desired():
    spec = importlib.util.spec_from_file_location("desired", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DesiredStateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_desired()
        cls.result = cls.module.generate(SERVARR)
        cls.expected = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_projection_matches_reviewed_fixture(self):
        observed = {
            "desired_sha256": self.result["desired_sha256"],
            "service_count": len(self.result["desired"]["services"]),
            "services": [
                [service["project"], service["service"], service["container_name"], service["digest_status"]]
                for service in self.result["desired"]["services"]
            ],
        }
        self.assertEqual(observed, self.expected)
        self.assertEqual(self.result, self.module.generate(SERVARR))

    def test_profiles_and_secret_contract_are_bound(self):
        desired = self.result["desired"]
        self.assertEqual(desired["stacks"], ["infra", "ai-serving", "docs-search", "orchestration"])
        self.assertEqual(desired["servarr_commit"], self.module.SERVARR_COMMIT)
        self.assertEqual(desired["secretspec_project"], "kepler")
        self.assertEqual(set(desired["source_sha256"]), {
            "infra.compose.yml", "ai-serving.compose.yml", "docs-search.compose.yml",
            "orchestration.compose.yml", "secretspec.toml",
        })
        projects = {service["project"] for service in desired["services"]}
        self.assertEqual(projects, set(desired["stacks"]))
        self.assertIn("restate", {service["container_name"] for service in desired["services"]})

    def test_only_value_free_fields_are_emitted(self):
        rendered = json.dumps(self.result, sort_keys=True)
        for forbidden in ("password", "api_key", "token", "__k1_dummy_"):
            self.assertNotIn(forbidden, rendered.lower())
        allowed = {
            "container_name", "digest_status", "image", "mounts", "networks",
            "project", "required_labels", "service",
        }
        self.assertTrue(all(set(service) == allowed for service in self.result["desired"]["services"]))

    def test_every_service_has_exact_compose_identity_labels(self):
        for service in self.result["desired"]["services"]:
            self.assertEqual(service["required_labels"], {
                "com.docker.compose.project": service["project"],
                "com.docker.compose.service": service["service"],
            })

    def test_revision_and_compose_drift_halt_or_change_binding(self):
        with self.assertRaises(self.module.DesiredHalt):
            self.module.generate(SERVARR, "0" * 40)
        changed = copy.deepcopy(self.result["desired"])
        changed["services"][0]["image"] = "changed:tag"
        self.assertNotEqual(
            self.result["desired_sha256"],
            __import__("hashlib").sha256(self.module.canonical(changed)).hexdigest(),
        )

    def test_compose_receives_only_generated_environment(self):
        captured = []
        real_run = self.module.subprocess.run

        def inspect_run(command, *args, **kwargs):
            if tuple(command[:2]) == ("docker", "compose"):
                captured.append(kwargs["env"])
                self.assertIn("--env-file", command)
                self.assertIn("/dev/null", command)
                self.assertIn("--no-env-resolution", command)
            return real_run(command, *args, **kwargs)

        with mock.patch.object(self.module.subprocess, "run", side_effect=inspect_run):
            self.module.generate(SERVARR)
        self.assertTrue(captured)
        for environment in captured:
            self.assertEqual(set(environment) - {"PATH"}, set(self.module.VARIABLE_NAMES))
            self.assertTrue(all(
                value.startswith((self.module.DUMMY_PREFIX, "/" + self.module.DUMMY_PREFIX))
                for key, value in environment.items() if key != "PATH"
            ))


if __name__ == "__main__":
    unittest.main()
