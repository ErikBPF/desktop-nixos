import copy
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PLANNER = ROOT / "modules/hosts/discovery/_stateful-swag-preflight.py"
ADOPT = ROOT / "modules/hosts/discovery/_stateful-swag-adopt.sh"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/finalize-observation.json"


def load_planner():
    spec = importlib.util.spec_from_file_location("swag_finalize", PLANNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SwagFinalizeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.planner = load_planner()

    def setUp(self):
        self.observation = json.loads(FIXTURE.read_text())

    def test_v3_binds_all_predecessors_artifacts_runtime_and_dns(self):
        manifest = self.planner.plan_finalize(self.observation)
        self.assertEqual(manifest["version"], 3)
        self.assertEqual(manifest["mode"], "finalize-attempt-03")
        self.assertEqual(manifest["attempt_02"]["manifest_sha256"], "d8317282ce3f4716491c0c6a33c354c6dea12d4a02880cc8e3d6650bf3383fad")
        self.assertEqual(manifest["attempt_02"]["observation_sha256"], "c1696360b1feb06ddc02059605912a3d2ea2ec6f2fc3f8d7b9d2330eba9db303")
        self.assertEqual(manifest["attempt_02"]["phase_markers"], ["init-complete", "swag-complete"])
        self.assertEqual(manifest["attempt_02"]["top_level_entries"], ["authorization.json", "observation.json", "phases", "post-runtime.json"])
        self.assertEqual(len(manifest["attempt_02"]["present_artifacts"]), 3)
        self.assertEqual(len(manifest["attempt_02"]["absent_artifacts"]), 2)
        self.assertEqual(manifest["dns_file_metadata"]["owner"], "1000:1000")
        self.assertEqual(manifest["dns_file_metadata"]["mode"], "0600")

    def test_deterministic_hash_binding_rejects_every_drift_class(self):
        authorization = self.planner.finalize_envelope(self.planner.plan_finalize(self.observation))
        self.assertEqual(authorization, self.planner.finalize_envelope(self.planner.plan_finalize(copy.deepcopy(self.observation))))
        self.planner.verify_finalize(self.observation, authorization)
        paths = [
            ("attempt_01", "retained", "ledger", "sha256"),
            ("attempt_02", "present_artifacts", "post_runtime", "sha256"),
            ("attempt_02", "phase_markers"),
            ("attempt_02", "top_level_entries"),
            ("current_runtime", "containers", 0, "id"),
            ("servarr", "render_sha256"),
            ("dns_file_metadata", "owner"),
        ]
        for path in paths:
            changed = copy.deepcopy(self.observation)
            node = changed
            for key in path[:-1]: node = node[key]
            key = path[-1]
            node[key] = [] if key == "phase_markers" else ("0:0" if key == "owner" else "a" * 64)
            with self.subTest(path=path), self.assertRaises(self.planner.InventoryDrift):
                self.planner.verify_finalize(changed, authorization)

    def test_v3_shell_is_read_only_atomic_locked_and_revalidates_idempotently(self):
        source = ADOPT.read_text()
        self.assertIn("observe-attempt-03", source)
        self.assertIn("finalize-attempt-03", source)
        finalize = source[source.index("finalize_attempt_03_main()") : source.index("assert_workflow_contract()")]
        for forbidden in ("compose[@]", "docker stop", "docker start", "chmod", "chown", "force-recreate", " up "):
            self.assertNotIn(forbidden, finalize)
        for required in ("flock 9", "assert_finalize_binding", "assert_attempt_03_predecessors", "assert_current_desired_runtime", "assert_final_gates_v3", "mv \"$prepare\" \"$attempt_03\""):
            self.assertIn(required, finalize)
        self.assertLess(finalize.index("flock 9"), finalize.index("assert_finalize_binding"))
        self.assertIn("exact certificate SAN set differs", source)
        self.assertIn("1000:1000", source)
        self.assertIn("RestartCount", source)
        self.assertIn("StartedAt", source)
        self.assertIn("container_lifecycle_mutation", source)
        self.assertIn("png_sha256", source)
        self.assertIn("runtime_sha256", source)

    def test_hook_gate_precedes_required_certbot_dns01_dry_run(self):
        source = ADOPT.read_text()
        gates = source[source.index("assert_final_gates_v3()") : source.index("observe_attempt_03_main()")]
        self.assertIn("assert_no_certbot_hooks", source)
        self.assertLess(gates.index("assert_no_certbot_hooks"), gates.index("certbot renew --dry-run"))
        for hook in ("pre_hook", "post_hook", "renew_hook", "deploy_hook"):
            self.assertIn(hook, source)
        for directory in ("renewal-hooks/pre", "renewal-hooks/post", "renewal-hooks/deploy"):
            self.assertIn(directory, source)
        self.assertIn("Certbot renewal-hook directory is not empty", source)


if __name__ == "__main__":
    unittest.main()
