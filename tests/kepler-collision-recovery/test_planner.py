import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
PLANNER = ROOT / "modules/hosts/kepler/_collision_recovery_planner.py"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/inventory.json"


def load_planner():
    spec = importlib.util.spec_from_file_location("planner", PLANNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PlannerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.planner = load_planner()

    def setUp(self):
        self.inventory = json.loads(FIXTURE.read_text())

    def plan(self, inventory=None):
        return self.planner.plan(self.inventory if inventory is None else inventory)

    def container(self, name):
        return next(c for c in self.inventory["containers"] if c["name"] == name)

    def test_fixture_matrix_and_exact_phase_order(self):
        manifest = self.plan()
        classes = {item["name"]: item["classification"] for item in manifest["resources"]}
        self.assertEqual(classes["postgres"], "declared-migrate")
        self.assertEqual(classes["gitlab"], "retired-wipe")
        self.assertEqual(classes["airflow-webserver"], "retired-wipe")
        self.assertEqual(classes["restate"], "retired-wipe")
        self.assertEqual(manifest["migration_order"], ["infra", "docs-search"])

    def test_running_missing_labels_foreign_mount_mismatch_and_unknown_halt(self):
        mutations = [
            lambda c: c.update(state="running"),
            lambda c: c.update(labels_complete=False),
            lambda c: c.update(project="foreign"),
            lambda c: c.update(mounts=["/wrong:/var/lib/postgresql/data"]),
            lambda c: c.update(name="unknown", project="unknown"),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                inventory = copy.deepcopy(self.inventory)
                mutate(inventory["containers"][0])
                with self.assertRaises(self.planner.PlanHalt):
                    self.plan(inventory)

    def test_exact_retirement_and_protection_allowlists(self):
        policy = self.planner.POLICY
        self.assertEqual(policy["retired_services"], ["gitlab", "airflow", "restate"])
        self.assertEqual(policy["gitlab_containers"], ["gitlab", "gitlab-runner"])
        self.assertEqual(policy["airflow_containers"], [
            "airflow-webserver", "airflow-scheduler", "airflow-triggerer",
            "airflow-worker", "airflow-init",
        ])
        self.assertEqual(policy["gitlab_paths"], [
            "/fast/apps/gitlab/config", "/fast/apps/gitlab/logs",
            "/fast/apps/gitlab-runner", "/bulk/git",
        ])
        self.assertEqual(policy["airflow_paths"], [
            "/fast/apps/airflow/dags", "/fast/apps/airflow/plugins",
        ])
        self.assertEqual(policy["airflow_volumes"], ["airflow_logs", "airflow_config"])
        self.assertEqual(policy["airflow_databases"], ["airflow"])
        self.assertEqual(policy["retired_secrets"], [
            "GITLAB_RUNNER_TOKEN", "POSTGRES_DB_AIRFLOW", "AIRFLOW_FERNET_KEY",
            "AIRFLOW_SECRET_KEY", "AIRFLOW_ADMIN_PASSWORD",
        ])
        self.assertEqual(policy["restate_containers"], ["restate"])
        self.assertEqual(policy["restate_volumes"], ["restate_data"])
        forbidden_parents = {"/fast", "/fast/apps", "/bulk"}
        declared = set(policy["gitlab_paths"] + policy["airflow_paths"])
        self.assertTrue(forbidden_parents.isdisjoint(declared))

    def test_retired_selection_requires_exact_name_ownership_mount_volume_and_image(self):
        mutations = [
            lambda c: c.update(name="gitlab-surprise"),
            lambda c: c.update(project="infra"),
            lambda c: c.update(retired_kind="airflow"),
            lambda c: c.update(mounts=["/fast/apps/gitlab:/etc/gitlab"]),
            lambda c: c.update(volumes=["unknown"]),
            lambda c: c.update(image_service_specific=False),
            lambda c: c.update(image="docker.io/example/not-gitlab:17@sha256:" + "b" * 64),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                inventory = copy.deepcopy(self.inventory)
                mutate(next(c for c in inventory["containers"] if c["name"] == "gitlab"))
                with self.assertRaises(self.planner.PlanHalt):
                    self.plan(inventory)

    def test_restate_retirement_mismatches_halt(self):
        for field, value in [
            ("state", "running"), ("labels_complete", False),
            ("project", "foreign"), ("mounts", ["wrong:/restate-data"]),
        ]:
            with self.subTest(field=field):
                inventory = copy.deepcopy(self.inventory)
                next(c for c in inventory["containers"] if c["name"] == "restate")[field] = value
                with self.assertRaises(self.planner.PlanHalt):
                    self.plan(inventory)

    def test_shared_image_is_protected(self):
        self.inventory["image_references"] = {
            self.container("gitlab")["image"]: ["gitlab", "retained-user"]
        }
        manifest = self.plan()
        gitlab = next(x for x in manifest["resources"] if x["name"] == "gitlab")
        self.assertEqual(gitlab["image_action"], "protected-shared")

    def test_duplicate_image_user_records_are_deduplicated(self):
        image = self.container("gitlab")["image"]
        self.inventory["image_references"] = {image: ["gitlab", "gitlab"]}
        manifest = self.plan()
        gitlab = next(x for x in manifest["resources"] if x["name"] == "gitlab")
        self.assertEqual(gitlab["image_action"], "exact-retired-only")

    def test_immutable_registry_and_local_provenance_required(self):
        self.container("postgres")["image"] = "docker.io/library/postgres:17"
        with self.assertRaises(self.planner.PlanHalt):
            self.plan()
        self.container("postgres")["image"] += "@sha256:" + "a" * 64
        del self.inventory["local_artifacts"][1]["model_sha256"]
        with self.assertRaises(self.planner.PlanHalt):
            self.plan()

    def test_typed_local_artifacts_require_only_applicable_provenance(self):
        self.plan()
        image = copy.deepcopy(self.inventory)
        del image["local_artifacts"][0]["source_commit"]
        with self.assertRaises(self.planner.PlanHalt):
            self.plan(image)
        model = copy.deepcopy(self.inventory)
        del model["local_artifacts"][1]["version"]
        with self.assertRaises(self.planner.PlanHalt):
            self.plan(model)

    def test_every_persistent_mount_is_protected(self):
        self.inventory["persistent_mounts"].append({"source": "/bulk/outside"})
        with self.assertRaises(self.planner.PlanHalt):
            self.plan()

    def test_manifest_is_value_free_deterministic_and_hash_bound(self):
        first = self.plan()
        second = self.plan(json.loads(json.dumps(self.inventory, sort_keys=True)))
        self.assertEqual(first, second)
        encoded = self.planner.canonical(first)
        self.assertEqual(self.planner.manifest_hash(first), hashlib.sha256(encoded).hexdigest())
        rendered = encoded.decode()
        for forbidden in ("token_value", "secret_value", "environment"):
            self.assertNotIn(forbidden, rendered.lower())

    def test_inventory_drift_rejected(self):
        manifest = self.plan()
        changed = copy.deepcopy(self.inventory)
        changed["containers"][0]["state"] = "running"
        with self.assertRaises(self.planner.InventoryDrift):
            self.planner.verify_inventory(changed, manifest)

    def test_manifest_envelope_binds_manifest_and_inventory(self):
        manifest = self.plan()
        envelope = {"manifest": manifest, "manifest_sha256": self.planner.manifest_hash(manifest)}
        self.planner.verify_envelope(self.inventory, envelope)
        changed_manifest = copy.deepcopy(envelope)
        changed_manifest["manifest"]["actions"] = []
        with self.assertRaises(self.planner.InventoryDrift):
            self.planner.verify_envelope(self.inventory, changed_manifest)
        changed_inventory = copy.deepcopy(self.inventory)
        changed_inventory["completed"] = ["postgres"]
        with self.assertRaises(self.planner.InventoryDrift):
            self.planner.verify_envelope(changed_inventory, envelope)

    def test_second_run_has_no_pending_actions(self):
        first = self.plan()
        self.inventory["completed"] = [
            {
                "resource": item["name"],
                "evidence_sha256": "9" * 64,
                "final_state": "retired-absent" if item["classification"] == "retired-wipe" else "replacement-validated",
            }
            for item in first["resources"] if item["classification"] != "noncollision"
        ]
        second = self.plan()
        self.assertEqual(second["actions"], [])

    def test_completion_is_evidence_and_state_bound(self):
        for completion in [
            {"resource": "postgres", "evidence_sha256": "short", "final_state": "replacement-validated"},
            {"resource": "postgres", "evidence_sha256": "9" * 64, "final_state": "retired-absent"},
        ]:
            inventory = copy.deepcopy(self.inventory)
            inventory["completed"] = [completion]
            with self.assertRaises(self.planner.PlanHalt):
                self.plan(inventory)

    def test_healthy_noncollision_is_in_scope_but_has_no_action(self):
        inventory = copy.deepcopy(self.inventory)
        resource = copy.deepcopy(inventory["containers"][0])
        resource.update(name="healthy", collision=False, state="running")
        inventory["containers"].append(resource)
        manifest = self.plan(inventory)
        classified = next(item for item in manifest["resources"] if item["name"] == "healthy")
        self.assertEqual(classified["classification"], "noncollision")
        self.assertNotIn("healthy", [action["resource"] for action in manifest["actions"]])

    def test_unknown_fields_and_value_aliases_are_rejected_recursively(self):
        mutations = [
            lambda i: i.update(environment=None),
            lambda i: i["containers"][0].update(env={}),
            lambda i: i["persistent_mounts"][0].update(secret_value=None),
            lambda i: i["local_artifacts"][0].update(token_value=None),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                inventory = copy.deepcopy(self.inventory)
                mutate(inventory)
                with self.assertRaises(self.planner.PlanHalt):
                    self.plan(inventory)

    def test_retired_manifest_selects_exact_value_free_resources(self):
        manifest = self.plan()
        gitlab = next(item for item in manifest["resources"] if item["name"] == "gitlab")
        airflow = next(item for item in manifest["resources"] if item["name"] == "airflow-webserver")
        self.assertEqual(gitlab["selected"]["paths"], sorted(self.planner.POLICY["gitlab_paths"]))
        self.assertEqual(gitlab["selected"]["secrets"], ["GITLAB_RUNNER_TOKEN"])
        self.assertEqual(airflow["selected"]["volumes"], sorted(self.planner.POLICY["airflow_volumes"]))
        self.assertEqual(airflow["selected"]["databases"], ["airflow"])

    def test_plan_has_no_destructive_command_or_automatic_expiry(self):
        rendered = json.dumps(self.plan(), sort_keys=True).lower()
        for forbidden in ("prune", "zfs destroy", "rm -r", "rollback", "snapshot delete"):
            self.assertNotIn(forbidden, rendered)
        self.assertEqual(self.plan()["retention"]["cleanup"], "separate-exact-resource-approval")

    def test_disposable_redis_reset_is_exact_hash_bound_and_has_no_backup(self):
        manifest = self.plan()
        self.assertEqual(manifest["redis_reset"], {
            "container": {"id": "2" * 64, "name": "redis", "state": "stopped"},
            "mode": "dry-run",
            "next": "declarative-infra-recreates-desired-redis",
            "project": "homelab",
            "service": "redis",
            "volume": {
                "driver": "local",
                "mountpoint": "/home/erik/.local/share/containers/storage/volumes/homelab_redis_data/_data",
                "name": "homelab_redis_data",
                "references": ["redis"],
            },
        })
        rendered = json.dumps(manifest["redis_reset"], sort_keys=True).lower()
        for forbidden in ("backup", "restore", "prune", "volume rm --all"):
            self.assertNotIn(forbidden, rendered)
        self.assertEqual(manifest["inventory_sha256"], self.planner.inventory_hash(self.inventory))
        phases = [operation["phase"] for operation in manifest["operations"]]
        self.assertLess(phases.index("postgres_checkpoint"), phases.index("redis_disposable_reset"))
        self.assertLess(phases.index("redis_disposable_reset"), phases.index("qdrant_idle"))

    def test_disposable_redis_reset_requires_exact_stopped_legacy_resources(self):
        mutations = (
            lambda item: item.update(container_id="short"),
            lambda item: item.update(container_name="redis-other"),
            lambda item: item.update(container_state="running"),
            lambda item: item.update(project="infra"),
            lambda item: item.update(service="other"),
            lambda item: item.update(volume_name="infra_redis_data"),
            lambda item: item.update(volume_driver="other"),
            lambda item: item.update(volume_references=[]),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                inventory = copy.deepcopy(self.inventory)
                mutation(inventory["redis_reset"])
                with self.assertRaises(self.planner.PlanHalt):
                    self.plan(inventory)

    def test_action_sequence_is_exact_and_dry_run_only(self):
        manifest = self.plan()
        self.assertEqual(manifest["phase_order"], [
            "inventory", "classify", "retained-database-backup-restore",
            "retired-secret-and-artifact-preflight", "retirement",
            "retained-state-protection", "infra", "docs-search",
            "reboot-validation", "retention",
        ])
        self.assertTrue(all(action["mode"] == "dry-run" for action in manifest["actions"]))

    def test_all_failure_phase_gates_halt_without_a_manifest(self):
        contract_failures = [
            ["inventory_collection"],
            ["classification"],
            ["retained_database_backup_restore"],
            ["retired_secret_revocation", "mixed_backup_sanitization", "exact_artifact_selection"],
            ["postgres_checkpoint", "redis_disposable_reset", "qdrant_idle", "minio_idle"],
            ["persistent_mount_coverage", "zfs_snapshot"],
            ["replacement_start"],
            ["replacement_validation", "reboot_validation"],
            ["cleanup_manifest_match"],
        ]
        for failure_number, gates in enumerate(contract_failures, start=1):
            for gate in gates:
                with self.subTest(failure=failure_number, gate=gate):
                    inventory = copy.deepcopy(self.inventory)
                    inventory["gates"][gate] = False
                    manifest = self.plan(inventory)
                    self.assertEqual(manifest["status"], "halt")
                    self.assertEqual(manifest["failed_gate"], gate)
                    reached = [operation["phase"] for operation in manifest["operations"]]
                    self.assertEqual(reached, self.planner.GATE_ORDER[:self.planner.GATE_ORDER.index(gate) + 1])
                    self.assertEqual(manifest["operations"][-1]["type"], "halt")
                    self.assertEqual(manifest["actions"], [])
                    if gate in {"inventory_collection", "classification"}:
                        self.assertEqual(manifest["resources"], [])
                    rendered = json.dumps(manifest["operations"]).lower()
                    self.assertIn("quarantined-containers", rendered)
                    self.assertIn("snapshots", rendered)
                    self.assertNotIn("legacy restart", rendered)
                    self.assertNotIn("dataset rollback", rendered)
        completed = copy.deepcopy(self.inventory)
        completed["completed"] = [
            {"resource": "postgres", "evidence_sha256": "9" * 64, "final_state": "replacement-validated"},
            {"resource": "gitlab", "evidence_sha256": "8" * 64, "final_state": "retired-absent"},
            {"resource": "airflow-webserver", "evidence_sha256": "7" * 64, "final_state": "retired-absent"},
            {"resource": "restate", "evidence_sha256": "6" * 64, "final_state": "retired-absent"},
        ]
        self.assertEqual(self.plan(completed)["actions"], [])


if __name__ == "__main__":
    unittest.main()
