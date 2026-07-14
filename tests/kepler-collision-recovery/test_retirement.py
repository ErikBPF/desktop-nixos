import copy
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_retirement.py"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/retirement-evidence.json"
INVENTORY = ROOT / ".gsd/evidence/kepler-k1/inventory.json"
JUSTFILE = ROOT / "justfile"


def load_module():
    spec = importlib.util.spec_from_file_location("retirement", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RetirementPlannerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.evidence = json.loads(FIXTURE.read_text())
        for reference in self.evidence["proofs"].values():
            reference["sha256"] = self.module.digest(reference["envelope"])
        for item in self.evidence["dispositions"]["containers"]:
            item["mount_retention"]["sha256"] = self.module.digest(item["mount_retention"]["envelope"])
        artifact = self.evidence["dispositions"]["artifacts"][0]
        artifact["path_evidence_sha256"] = self.evidence["proofs"]["retirement_paths"]["sha256"]
        self.inventory = {
            "schema": "kepler-collision-inventory-envelope-v1",
            "inventory_sha256": "a" * 64,
            "inventory": {"containers": [
                {"name": item["name"], "id": item["id"], "state": item["state"], "mounts": [{"source": source} for source in item["mount_retention"]["envelope"]["sources"]]}
                for item in self.evidence["dispositions"]["containers"]
            ] + [
                {"name": item["name"], "id": item["id"], "state": item["state"], "mounts": []}
                for family in self.evidence["retired"] for item in family["containers"]
            ], "volumes": [
                {"name": "airflow_airflow_config", "labels": {"com.docker.compose.project": "airflow", "com.docker.compose.volume": "airflow_config"}},
                {"name": "airflow_airflow_logs", "labels": {"com.docker.compose.project": "airflow", "com.docker.compose.volume": "airflow_logs"}},
                {"name": "orchestration_restate_data", "labels": {"com.docker.compose.project": "orchestration", "com.docker.compose.volume": "restate_data"}}
            ], "images": [
                {"id": "1" * 64, "digests": ["docker.io/gitlab/gitlab-ce@sha256:" + "a" * 64]},
                {"id": "2" * 64, "digests": ["docker.io/apache/airflow@sha256:" + "b" * 64]},
                {"id": "3" * 64, "digests": ["docker.restate.dev/restatedev/restate@sha256:" + "c" * 64]}
                ,{"id": "3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b", "digests": [], "names": ["docker.io/kepler/f5-tts-server:pt-br"]}
            ], "references": {"images": {
                "sha256:" + "1" * 64: ["gitlab", "gitlab-runner"],
                "sha256:" + "2" * 64: ["airflow-init", "airflow-scheduler", "airflow-triggerer", "airflow-webserver", "airflow-worker"],
                "sha256:" + "3" * 64: ["restate"]
                ,"sha256:3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b": ["f5-tts-server"]
            }}},
        }
        self.inventory["schema"] = "kepler-collision-inventory-v1"
        self.inventory["inventory_sha256"] = self.module.digest(self.inventory["inventory"])
        self.evidence["inventory_sha256"] = self.inventory["inventory_sha256"]
        database_reference = self.evidence["proofs"]["retained_database_restore"]
        database_reference["envelope"]["manifest"]["inventory_sha256"] = self.inventory["inventory_sha256"]
        database_reference["envelope"]["manifest_sha256"] = self.module.digest(database_reference["envelope"]["manifest"])
        database_reference["sha256"] = self.module.digest(database_reference["envelope"])
        preflight_reference = self.evidence["proofs"]["retired_preflight"]
        preflight_reference["sha256"] = self.module.digest(preflight_reference["envelope"])
        for family in self.evidence["retired"]:
            resources = {key: family[key] for key in (
                "family", "containers", "paths", "volumes", "databases", "secrets", "images"
            )}
            reference = family["family_evidence"]
            reference["envelope"]["resources_sha256"] = self.module.digest(resources)
            reference["envelope"]["path_identities"] = [
                {"path": path, "envelope_sha256": self.evidence["proofs"]["retirement_paths"]["sha256"]}
                for path in family["paths"]
            ]
            reference["sha256"] = self.module.digest(reference["envelope"])

    def test_remote_executor_receives_validated_literal_bindings(self):
        recipe = JUSTFILE.read_text()
        self.assertIn(
            '--manifest-sha256 "{{manifest_sha256}}" --inventory-sha256 "{{inventory_sha256}}"',
            recipe,
        )
        self.assertIn('"{{manifest_sha256}}" =~ ^[0-9a-f]{64}$', recipe)

    def plan(self):
        return self.module.plan(self.inventory, self.evidence)

    def rebind(self, inventory, evidence=None):
        evidence = self.evidence if evidence is None else evidence
        inventory["inventory_sha256"] = self.module.digest(inventory["inventory"])
        evidence["inventory_sha256"] = inventory["inventory_sha256"]
        reference = evidence["proofs"]["retained_database_restore"]
        reference["envelope"]["manifest"]["inventory_sha256"] = inventory["inventory_sha256"]
        reference["envelope"]["manifest_sha256"] = self.module.digest(reference["envelope"]["manifest"])
        reference["sha256"] = self.module.digest(reference["envelope"])

    def test_exact_policy_and_user_dispositions(self):
        manifest = self.plan()
        self.assertEqual(manifest["retired_allowlist"], self.module.RETIRED_ALLOWLIST)
        self.assertEqual([x["name"] for x in manifest["disposition_resources"]],
                         ["f5-tts-image", "f5-tts-model-data", "f5-tts-server", "ha-train-run", "minicpm-train", "uv_build"])

    def test_restate_is_exact_disposable_retired_family(self):
        manifest = self.plan()
        policy = manifest["retired_allowlist"]["restate"]
        self.assertEqual(policy, {
            "containers": ["restate"], "paths": [], "volumes": ["restate_data"],
            "databases": [], "secrets": [],
        })
        restate = next(item for item in manifest["retired_resources"] if item["family"] == "restate")
        self.assertEqual(restate["volumes"][0]["runtime_name"], "orchestration_restate_data")
        self.assertNotIn("restate_data", [item["resource"] for item in manifest["actions"] if item["kind"] == "path"])

    def test_already_absent_families_are_idempotent(self):
        for family in self.evidence["retired"]:
            family.update(containers=[], paths=[], volumes=[], databases=[], secrets=[], images=[])
        self.inventory["inventory"]["containers"] = [
            item for item in self.inventory["inventory"]["containers"]
            if item["name"] in self.module.DISPOSITION_CONTAINERS
        ]
        self.inventory["inventory"]["volumes"] = []
        self.inventory["inventory"]["images"] = [self.inventory["inventory"]["images"][-1]]
        self.inventory["inventory"]["references"]["images"] = {"sha256:3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b": ["f5-tts-server"]}
        self.rebind(self.inventory)
        for family in self.evidence["retired"]:
            resources = {key: family[key] for key in ("family", "containers", "paths", "volumes", "databases", "secrets", "images")}
            reference = family["family_evidence"]
            reference["envelope"].update(resources_sha256=self.module.digest(resources), path_identities=[])
            reference["sha256"] = self.module.digest(reference["envelope"])
        manifest = self.plan()
        self.assertTrue(all(not any(item[field] for field in ("containers", "paths", "volumes", "databases", "secrets", "images")) for item in manifest["retired_resources"]))

    def test_gitlab_image_only_inventory_is_selectable(self):
        for family in self.evidence["retired"]:
            family.update(containers=[], paths=[], volumes=[], databases=[], secrets=[])
            if family["family"] != "gitlab":
                family["images"] = []
            resources = {key: family[key] for key in ("family", "containers", "paths", "volumes", "databases", "secrets", "images")}
            reference = family["family_evidence"]
            reference["envelope"].update(resources_sha256=self.module.digest(resources), path_identities=[])
            reference["sha256"] = self.module.digest(reference["envelope"])
        self.inventory["inventory"]["containers"] = [item for item in self.inventory["inventory"]["containers"] if item["name"] in self.module.DISPOSITION_CONTAINERS]
        self.inventory["inventory"]["volumes"] = []
        self.inventory["inventory"]["images"] = [self.inventory["inventory"]["images"][0], self.inventory["inventory"]["images"][-1]]
        self.inventory["inventory"]["references"]["images"] = {"sha256:" + "1" * 64: [], "sha256:3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b": ["f5-tts-server"]}
        self.rebind(self.inventory)
        manifest = self.plan()
        self.assertIn("sha256:" + "1" * 64, [action["resource"] for action in manifest["actions"]])

    def test_never_infers_retired_or_disposition_by_substring(self):
        bad = copy.deepcopy(self.evidence)
        bad["retired"][0]["containers"].append({"name": "gitlab-old", "id": "8" * 64, "state": "exited"})
        with self.assertRaisesRegex(self.module.RetirementHalt, "exact allowlist"):
            self.module.plan(self.inventory, bad)
        bad = copy.deepcopy(self.evidence)
        bad["dispositions"]["containers"][0]["name"] = "ha-train-run-old"
        with self.assertRaisesRegex(self.module.RetirementHalt, "disposition allowlist"):
            self.module.plan(self.inventory, bad)

    def test_container_requires_exact_live_id_stopped_state_and_retention_evidence(self):
        for field, value, message in [
            ("id", "9" * 64, "inventory ID mismatch"),
            ("state", "running", "must be exited"),
            ("mount_retention", {"sha256": "short", "envelope": {}}, "mount retention"),
        ]:
            with self.subTest(field=field):
                bad = copy.deepcopy(self.evidence)
                next(item for item in bad["dispositions"]["containers"] if item["name"] == "ha-train-run")[field] = value
                with self.assertRaisesRegex(self.module.RetirementHalt, message):
                    self.module.plan(self.inventory, bad)

    def test_f5_requires_exact_discovered_path_and_hash_evidence(self):
        for field, value in [
            ("name", "f5-tts-checkpoint-old"),
            ("path", "/fast/ai-models"),
            ("path_evidence_sha256", "short"),
        ]:
            with self.subTest(field=field):
                bad = copy.deepcopy(self.evidence)
                bad["dispositions"]["artifacts"][0][field] = value
                with self.assertRaises(self.module.RetirementHalt):
                    self.module.plan(self.inventory, bad)

    def test_f5_live_container_image_and_model_path_are_exact_without_refs_delete(self):
        manifest = self.plan()
        actions = manifest["actions"]
        self.assertIn("06e6797be6509c8b36596e6914b8ae878e6abaf7f525e2a35836f0dc3ca7ea00", [item["command"][-1] for item in actions])
        self.assertIn("sha256:3564ddece33dca13c11c302779951f64550297b90c7c93042f5522db527e8b9b", [item["resource"] for item in actions])
        self.assertIn("/fast/ai-models/f5-tts", [item["resource"] for item in actions])
        self.assertNotIn("/fast/ai-models/refs", [item["resource"] for item in actions])

    def test_deterministic_value_free_hash_bound_dry_run(self):
        first = self.plan()
        second = self.module.plan(copy.deepcopy(self.inventory), copy.deepcopy(self.evidence))
        self.assertEqual(first, second)
        envelope = self.module.envelope(first)
        self.module.verify(self.inventory, self.evidence, envelope)
        rendered = json.dumps(envelope, sort_keys=True)
        self.assertNotRegex(rendered.lower(), r"secret_value|token_value|environment")
        self.assertTrue(all(x["mode"] == "dry-run" for x in first["actions"]))

    def test_exact_commands_abort_and_irreversible_boundaries(self):
        manifest = self.plan()
        for action in manifest["actions"]:
            self.assertIsInstance(action["command"], list)
            self.assertEqual(action["abort"], "before-command")
            self.assertIn(action["rollback"], {"not-applicable-after-exact-delete", "not-applicable-disposable-test"})
        rendered = json.dumps([action["command"] for action in manifest["actions"]]).lower()
        for forbidden in ["prune", "zfs destroy", "rm -r", "/fast/apps\"", "/fast\""]:
            self.assertNotIn(forbidden, rendered)

    def test_inventory_or_manifest_drift_rejected(self):
        envelope = self.module.envelope(self.plan())
        changed = copy.deepcopy(self.inventory)
        changed["inventory"]["containers"][0]["state"] = "exited"
        with self.assertRaises(self.module.RetirementDrift):
            self.module.verify(changed, self.evidence, envelope)
        envelope["manifest"]["actions"] = []
        with self.assertRaises(self.module.RetirementDrift):
            self.module.verify(self.inventory, self.evidence, envelope)

    def test_unknown_fields_and_execute_mode_rejected(self):
        bad = copy.deepcopy(self.evidence)
        bad["execute"] = True
        with self.assertRaises(self.module.RetirementHalt):
            self.module.plan(self.inventory, bad)

    def test_referenced_evidence_hash_and_status_are_required(self):
        for proof in ["retained_database_restore", "retired_preflight"]:
            with self.subTest(proof=proof):
                bad = copy.deepcopy(self.evidence)
                bad["proofs"][proof]["sha256"] = "f" * 64
                with self.assertRaisesRegex(self.module.RetirementHalt, "evidence hash mismatch"):
                    self.module.plan(self.inventory, bad)

    def test_database_planner_manifest_is_exactly_authenticated(self):
        mutations = [
            lambda m: m.update(inventory_sha256="f" * 64),
            lambda m: m["retained_databases"].pop(),
            lambda m: m["cluster_artifact"].update(sha256="f" * 64),
            lambda m: m["cluster_restore"].update(artifact_sha256="f" * 64),
            lambda m: m["cluster_restore"].update(retained_databases=["app"]),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                bad = copy.deepcopy(self.evidence)
                reference = bad["proofs"]["retained_database_restore"]
                mutate(reference["envelope"]["manifest"])
                reference["envelope"]["manifest_sha256"] = self.module.digest(reference["envelope"]["manifest"])
                reference["sha256"] = self.module.digest(reference["envelope"])
                with self.assertRaises(self.module.RetirementHalt):
                    self.module.plan(self.inventory, bad)

    def test_preflight_requires_exact_declared_coverage_sets(self):
        bad = copy.deepcopy(self.evidence)
        reference = bad["proofs"]["retired_preflight"]
        reference["envelope"]["secret_artifacts"] = ["OUTSIDE_ALLOWLIST"]
        reference["sha256"] = self.module.digest(reference["envelope"])
        with self.assertRaises(self.module.RetirementHalt):
            self.module.plan(self.inventory, bad)
        bad = copy.deepcopy(self.evidence)
        reference = bad["proofs"]["retired_preflight"]
        reference["envelope"].update(declared_secrets=["GITLAB_RUNNER_TOKEN"], secret_artifacts=["GITLAB_RUNNER_TOKEN"], external_credentials=["GITLAB_RUNNER_TOKEN"], external_revocations=[])
        reference["sha256"] = self.module.digest(reference["envelope"])
        with self.assertRaisesRegex(self.module.RetirementHalt, "external revocation"):
            self.module.plan(self.inventory, bad)

    def test_family_evidence_is_hash_and_exact_resource_bound(self):
        bad = copy.deepcopy(self.evidence)
        bad["retired"][0]["family_evidence"]["sha256"] = "f" * 64
        with self.assertRaisesRegex(self.module.RetirementHalt, "evidence hash mismatch"):
            self.module.plan(self.inventory, bad)
        bad = copy.deepcopy(self.evidence)
        reference = bad["retired"][0]["family_evidence"]
        reference["envelope"]["resources_sha256"] = "f" * 64
        reference["sha256"] = self.module.digest(reference["envelope"])
        with self.assertRaisesRegex(self.module.RetirementHalt, "family evidence resource mismatch"):
            self.module.plan(self.inventory, bad)

    def test_duplicate_inventory_volume_and_image_identities_rejected(self):
        for field in ["volumes", "images"]:
            with self.subTest(field=field):
                inventory = copy.deepcopy(self.inventory)
                evidence = copy.deepcopy(self.evidence)
                inventory["inventory"][field].append(copy.deepcopy(inventory["inventory"][field][0]))
                self.rebind(inventory, evidence)
                with self.assertRaisesRegex(self.module.RetirementHalt, "duplicate inventory"):
                    self.module.plan(inventory, evidence)
    def test_inventory_internal_hash_is_validated_before_use(self):
        bad = copy.deepcopy(self.inventory)
        bad["inventory"]["containers"][0]["state"] = "exited"
        with self.assertRaisesRegex(self.module.RetirementHalt, "inventory internal SHA-256 mismatch"):
            self.module.plan(bad, self.evidence)

    def test_mount_and_path_reference_hashes_are_validated(self):
        bad = copy.deepcopy(self.evidence)
        bad["dispositions"]["containers"][0]["mount_retention"]["sha256"] = "f" * 64
        with self.assertRaisesRegex(self.module.RetirementHalt, "evidence hash mismatch"):
            self.module.plan(self.inventory, bad)
        bad = copy.deepcopy(self.evidence)
        bad["proofs"]["retirement_paths"]["sha256"] = "f" * 64
        with self.assertRaisesRegex(self.module.RetirementHalt, "evidence hash mismatch"):
            self.module.plan(self.inventory, bad)

    def test_runtime_volumes_require_exact_compose_labels(self):
        bad = copy.deepcopy(self.inventory)
        bad["inventory"]["volumes"][0]["labels"]["com.docker.compose.volume"] = "other"
        evidence = copy.deepcopy(self.evidence)
        self.rebind(bad, evidence)
        with self.assertRaisesRegex(self.module.RetirementHalt, "runtime volume label mismatch"):
            self.module.plan(bad, evidence)

    def test_images_are_inventory_bound_and_unshared(self):
        bad = copy.deepcopy(self.inventory)
        bad["inventory"]["images"][0]["id"] = "9" * 64
        evidence = copy.deepcopy(self.evidence)
        self.rebind(bad, evidence)
        with self.assertRaisesRegex(self.module.RetirementHalt, "image identity absent"):
            self.module.plan(bad, evidence)
        bad = copy.deepcopy(self.inventory)
        bad["inventory"]["references"]["images"]["sha256:" + "1" * 64].append("retained-service")
        evidence = copy.deepcopy(self.evidence)
        self.rebind(bad, evidence)
        with self.assertRaisesRegex(self.module.RetirementHalt, "shared image"):
            self.module.plan(bad, evidence)

    def test_f5_normalization_and_identity_binding(self):
        bad = copy.deepcopy(self.evidence)
        artifact = bad["dispositions"]["artifacts"][0]
        artifact["path"] = "/fast/ai-models/../ai-models/f5-tts"
        with self.assertRaisesRegex(self.module.RetirementHalt, "normalized"):
            self.module.plan(self.inventory, bad)
        bad = copy.deepcopy(self.evidence)
        artifact = bad["dispositions"]["artifacts"][0]
        path_reference = bad["proofs"]["retirement_paths"]
        path_reference["envelope"]["paths"][0]["existence"] = False
        path_reference["sha256"] = self.module.digest(path_reference["envelope"])
        artifact["path_evidence_sha256"] = path_reference["sha256"]
        for family in bad["retired"]:
            for item in family["family_evidence"]["envelope"].get("path_identities", []):
                item["envelope_sha256"] = path_reference["sha256"]
            family["family_evidence"]["sha256"] = self.module.digest(family["family_evidence"]["envelope"])
        with self.assertRaisesRegex(self.module.RetirementHalt, "path identity mismatch"):
            self.module.plan(self.inventory, bad)


if __name__ == "__main__":
    unittest.main()
