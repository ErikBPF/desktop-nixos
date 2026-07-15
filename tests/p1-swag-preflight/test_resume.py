import copy
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PLANNER = ROOT / "modules/hosts/discovery/_stateful-swag-preflight.py"
ADOPT = ROOT / "modules/hosts/discovery/_stateful-swag-adopt.sh"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/resume-observation.json"


def load_planner():
    spec = importlib.util.spec_from_file_location("swag_resume", PLANNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SwagResumeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.planner = load_planner()

    def setUp(self):
        self.observation = json.loads(FIXTURE.read_text())

    def test_versioned_manifest_binds_predecessor_retained_and_runtime(self):
        manifest = self.planner.plan_resume(self.observation)
        self.assertEqual(manifest["version"], 2)
        self.assertEqual(
            manifest["retained"]["snapshot"]["uuid"],
            "99999999-9999-0999-0999-999999999999",
        )
        self.assertEqual(manifest["predecessor"], {
            "inventory_sha256": "35c294e9fe74e8b824df7aa8161693bfd555f09b97d1ef36b58a280d08d521e7",
            "manifest_sha256": "ee7861b9789f08a6fb0319ba931760054625d3e1cabe03bf43443560db3daee7",
        })
        self.assertEqual(set(manifest["retained"]), {"authorization", "approved_inventory", "ledger", "archive", "archive_checksum", "snapshot"})
        self.assertEqual([x["name"] for x in manifest["current_runtime"]["containers"]], ["swag", "swag-init"])
        self.assertEqual(manifest["dns_file_metadata"], {
            "mode": "0600",
            "owner": "0:0",
            "path": "/home/erik/servarr/machines/discovery/config/swag/dns-conf/cloudflare.ini",
        })
        self.assertEqual(manifest["servarr"], self.observation["servarr"])

    def test_deterministic_value_free_hash_bound_and_idempotent(self):
        first = self.planner.resume_envelope(self.planner.plan_resume(self.observation))
        second = self.planner.resume_envelope(self.planner.plan_resume(copy.deepcopy(self.observation)))
        self.assertEqual(first, second)
        self.planner.verify_resume(self.observation, first)
        rendered = json.dumps(first).lower()
        for token in ("secret_value", "token_value", "password", "credential", "environment"):
            self.assertNotIn(token, rendered)

    def test_tamper_collision_and_runtime_drift_halt(self):
        authorization = self.planner.resume_envelope(self.planner.plan_resume(self.observation))
        cases = []
        tampered = copy.deepcopy(self.observation)
        tampered["retained"]["ledger"]["sha256"] = "a" * 64
        cases.append(tampered)
        collision = copy.deepcopy(self.observation)
        collision["retained"]["ledger"]["path"] = collision["retained"]["archive"]["path"]
        cases.append(collision)
        drift = copy.deepcopy(self.observation)
        drift["current_runtime"]["containers"][0]["id"] = "a" * 64
        cases.append(drift)
        for changed in cases:
            with self.subTest(changed=changed), self.assertRaises(self.planner.InventoryDrift):
                self.planner.verify_resume(changed, authorization)

    def test_initial_failed_credential_transition_is_exact(self):
        authorization = self.planner.resume_envelope(self.planner.plan_resume(self.observation))
        self.planner.verify_resume(self.observation, authorization)
        for key, value in (("owner", "1000:100"), ("owner", "0:100"), ("mode", "0640"), ("path", "/tmp/cloudflare.ini")):
            changed = copy.deepcopy(self.observation)
            changed["dns_file_metadata"][key] = value
            with self.subTest(key=key, value=value), self.assertRaises(self.planner.InventoryDrift):
                self.planner.verify_resume(changed, authorization)

    def test_compose_commit_render_and_path_drift_halt(self):
        authorization = self.planner.resume_envelope(self.planner.plan_resume(self.observation))
        for key, value in (("commit", "c" * 40), ("render_sha256", "d" * 64), ("compose_file", "/tmp/networking.yml")):
            changed = copy.deepcopy(self.observation)
            changed["servarr"][key] = value
            with self.subTest(key=key), self.assertRaises(self.planner.InventoryDrift):
                self.planner.verify_resume(changed, authorization)

    def test_swag_init_runtime_drift_halts(self):
        authorization = self.planner.resume_envelope(self.planner.plan_resume(self.observation))
        for key, value in (("state", "running"), ("id", "e" * 64), ("image_ref", "busybox:latest")):
            changed = copy.deepcopy(self.observation)
            init = next(item for item in changed["current_runtime"]["containers"] if item["name"] == "swag-init")
            init[key] = value
            with self.subTest(key=key), self.assertRaises(self.planner.InventoryDrift):
                self.planner.verify_resume(changed, authorization)

    def test_attempt_two_paths_and_order_are_fixed_and_no_clobber(self):
        manifest = self.planner.plan_resume(self.observation)
        self.assertTrue(all("attempt-02" in path for path in manifest["attempt_evidence"].values()))
        self.assertEqual(manifest["workflow_contract"]["execute_order"], [
            "verify-predecessor-and-retained-evidence",
            "capture-and-bind-post-recreate-runtime",
            "validate-attempt-02-no-clobber-evidence-set",
            "persist-attempt-02-authorization-and-observation",
            "recreate-swag-init",
            "recreate-swag",
            "validate-owner-mode-health-certificate-dns-and-routes",
            "persist-attempt-02-result",
        ])
        self.assertEqual(manifest["workflow_contract"]["phase_markers"], ["init-complete", "swag-complete", "validation-complete"])
        self.assertEqual(manifest["workflow_contract"]["resume_policy"]["markers"], "monotonic-no-overwrite")
        self.assertEqual(manifest["workflow_contract"]["resume_policy"]["compose_consistency"], "declarative-no-interpolate-hash-before-and-after-each-up")
        source = ADOPT.read_text()
        self.assertIn("resume-attempt-02", source)
        self.assertIn("observe-attempt-02", source)
        self.assertNotIn("rm -rf", source)
        resume = source[source.index("resume_attempt_02_main()") :]
        self.assertLess(resume.index("exit-code-from swag-init swag-init"), resume.index("force-recreate swag\n"))

    def test_resume_preserves_predecessor_and_keeps_all_original_gates(self):
        source = ADOPT.read_text()
        resume = source[source.index("resume_attempt_02_main()") : source.index("execute_main()")]
        for required in (
            'assert_retained_binding "$predecessor_manifest_sha"',
            'sha256sum "$archive"',
            'assert_dns_owner_mode',
            'capture_resume_observation "$runtime" "$observation"',
            "= 600",
            "= 1000:100",
            "SWAG failed health gate",
            "certificate expires within seven days",
            "wildcard SAN absent",
            "certbot renew --dry-run",
            "grafana.homelab.pastelariadev.com",
            "adguard.homelab.pastelariadev.com",
            "kindle.homelab.pastelariadev.com",
        ):
            self.assertIn(required, source if required in ("= 600", "= 1000:100", "SWAG failed health gate", "certificate expires within seven days", "wildcard SAN absent", "certbot renew --dry-run", "grafana.homelab.pastelariadev.com", "adguard.homelab.pastelariadev.com", "kindle.homelab.pastelariadev.com") else resume)
        self.assertNotIn('--output "$kindle_png"', resume)

    def test_successful_second_run_returns_before_compose(self):
        source = ADOPT.read_text()
        resume = source[source.index("resume_attempt_02_main()") : source.index("execute_main()")]
        no_op = resume.index('cat "$attempt_02_result"')
        early_return = resume.index("return", no_op)
        compose = resume.index("compose=(", early_return)
        self.assertLess(no_op, early_return)
        self.assertLess(early_return, compose)

    def test_partial_resume_and_noop_revalidate_current_state(self):
        source = ADOPT.read_text()
        for required in (
            "init-complete", "swag-complete", "validation-complete",
            "assert_phase_journal_shape",
            "assert_retained_resume_hashes",
            "assert_fresh_compose_binding", "assert_stored_resume_binding",
            "assert_current_desired_runtime", "assert_final_gates",
            "current SWAG identity is neither approved pre-state nor desired post-state",
            "current swag-init identity differs",
        ):
            self.assertIn(required, source)
        self.assertIn("--no-interpolate", source)
        self.assertIn("--no-env-resolution", source)
        self.assertNotIn('-f "$compose_file" config 2>/dev/null', source)
        self.assertIn('current_init_id" != "$initial_init_id', source)
        self.assertIn('current_swag_id" = "$initial_swag_id', source)
        self.assertGreaterEqual(source.count('assert_fresh_compose_binding "$attempt_02_authorization"'), 6)
        no_op = source[source.index("resume_attempt_02_main()") : source.index("return", source.index("# A fully recorded successful attempt"))]
        for required in ("assert_retained_binding", "assert_stored_resume_binding", "assert_fresh_compose_binding", "assert_current_desired_runtime", "assert_final_gates"):
            self.assertIn(required, no_op)

    def test_pull_and_resume_share_one_repository_lock(self):
        orchestration = (ROOT / "modules/server/orchestration.nix").read_text()
        adopt = ADOPT.read_text()
        self.assertIn("/run/lock/servarr-repository.lock", orchestration)
        self.assertIn("/run/lock/servarr-repository.lock", adopt)
        self.assertIn("0660 root users", orchestration)
        self.assertNotIn("/run/user/", adopt)
        self.assertIn("flock 9", orchestration)
        resume = adopt[adopt.index("resume_attempt_02_main()") :]
        self.assertLess(resume.index("flock 9"), resume.index("assert_fresh_compose_binding"))

    def test_normal_returns_disarm_local_cleanup_traps(self):
        source = ADOPT.read_text()
        observe = source[source.index("observe_attempt_02_main()") : source.index("assert_fresh_compose_binding()")]
        resume = source[source.index("resume_attempt_02_main()") : source.index("assert_workflow_contract()")]
        self.assertIn("trap - EXIT", observe)
        self.assertGreaterEqual(resume.count("trap - EXIT"), 2)


if __name__ == "__main__":
    unittest.main()
