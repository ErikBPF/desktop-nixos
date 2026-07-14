import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_database_evidence.py"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/database-evidence.json"


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def load_module():
    spec = importlib.util.spec_from_file_location("database_evidence", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DatabaseEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.evidence = json.loads(FIXTURE.read_text())
        self.inventory = {
            "schema": "kepler-collision-inventory-v1",
            "inventory": {"containers": [{"id": "b" * 64, "name": "postgres"}]},
            "inventory_sha256": digest({"containers": [{"id": "b" * 64, "name": "postgres"}]}),
        }
        self.evidence["inventory_sha256"] = self.inventory["inventory_sha256"]

    def plan(self):
        return self.module.plan(
            self.inventory, self.evidence, self.inventory["inventory_sha256"]
        )

    def test_emits_deterministic_hash_bound_value_free_gate(self):
        first = self.plan()
        self.assertEqual(first, self.plan())
        self.assertEqual(first["manifest_sha256"], digest(first["manifest"]))
        self.assertEqual(
            first["manifest"]["inventory_sha256"], self.inventory["inventory_sha256"]
        )
        self.assertEqual(first["manifest"]["status"], "retained-databases-verified")
        rendered = json.dumps(first, sort_keys=True).lower()
        for forbidden in ("password", "secret", "connection", "environment", "contents"):
            self.assertNotIn(forbidden, rendered)

    def test_records_exact_identities_and_one_restore_tested_cluster_artifact(self):
        manifest = self.plan()["manifest"]
        retained = manifest["retained_databases"]
        self.assertEqual([item["name"] for item in retained], ["app", "postgres"])
        self.assertEqual(retained[0]["owner"], "app_owner")
        self.assertEqual(set(manifest["cluster_artifact"]), {"bytes", "created_at", "sha256"})
        self.assertEqual(
            manifest["cluster_restore"]["artifact_sha256"],
            manifest["cluster_artifact"]["sha256"],
        )
        self.assertEqual(manifest["cluster_restore"]["retained_databases"], ["app", "postgres"])

    def test_airflow_is_exact_retired_database_and_never_retained(self):
        manifest = self.plan()["manifest"]
        self.assertEqual(manifest["retired_databases"], ["airflow"])
        self.assertEqual(manifest["airflow_drop_gate"], "eligible-after-separate-approved-retirement-manifest")
        self.evidence["retired_databases"] = ["airflow", "other"]
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "retired database allowlist"):
            self.plan()
        self.evidence = json.loads(FIXTURE.read_text())
        self.evidence["inventory_sha256"] = self.inventory["inventory_sha256"]
        self.evidence["retained_databases"][0]["name"] = "airflow"
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "Airflow must not be retained"):
            self.plan()

    def test_rejects_failed_missing_or_duplicate_retained_evidence(self):
        mutations = (
            lambda e: e["cluster_restore"].update(status="failed"),
            lambda e: e["cluster_restore"].update(retained_databases=["postgres"]),
            lambda e: e["cluster_artifact"].update(bytes=0),
            lambda e: e["cluster_artifact"].pop("sha256"),
            lambda e: e["retained_databases"].append(copy.deepcopy(e["retained_databases"][0])),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                original = copy.deepcopy(self.evidence)
                mutation(self.evidence)
                with self.assertRaises(self.module.DatabaseEvidenceHalt):
                    self.plan()
                self.evidence = original

    def test_rejects_cluster_inventory_binding_drift(self):
        self.evidence["cluster_restore"]["database_inventory_sha256"] = "f" * 64
        with self.assertRaisesRegex(
            self.module.DatabaseEvidenceHalt, "database inventory binding mismatch"
        ):
            self.plan()

    def test_rejects_restore_not_bound_to_cluster_artifact_or_logical_hash(self):
        restore = self.evidence["cluster_restore"]
        restore["artifact_sha256"] = "f" * 64
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "artifact binding"):
            self.plan()
        self.evidence = json.loads(FIXTURE.read_text())
        self.evidence["inventory_sha256"] = self.inventory["inventory_sha256"]
        self.evidence["cluster_restore"]["logical_sha256"] = "short"
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "logical evidence"):
            self.plan()

    def test_requires_backup_for_every_discovered_non_airflow_database(self):
        self.evidence["retained_databases"].pop()
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "database inventory coverage"):
            self.plan()
        self.evidence = json.loads(FIXTURE.read_text())
        self.evidence["inventory_sha256"] = self.inventory["inventory_sha256"]
        self.evidence["database_inventory"][1]["owner"] = "wrong_owner"
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "database inventory coverage"):
            self.plan()

    def test_rejects_inventory_or_evidence_binding_drift(self):
        self.evidence["inventory_sha256"] = "d" * 64
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "evidence inventory drift"):
            self.plan()
        self.evidence["inventory_sha256"] = self.inventory["inventory_sha256"]
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "approval inventory drift"):
            self.module.plan(self.inventory, self.evidence, "e" * 64)
        self.inventory["inventory_sha256"] = "f" * 64
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "inventory SHA-256 mismatch"):
            self.module.plan(self.inventory, self.evidence, "f" * 64)

    def test_rejects_postgres_source_container_id_drift(self):
        self.evidence["source_container_id"] = "f" * 64
        with self.assertRaisesRegex(self.module.DatabaseEvidenceHalt, "source container identity drift"):
            self.plan()

    def test_commands_use_future_just_interfaces_and_are_non_executable(self):
        manifest = self.plan()["manifest"]
        self.assertFalse(manifest["execution_supported"])
        self.assertEqual(manifest["commands"], [
            "just kepler-recovery-postgres-backup <inventory-sha256>",
            "just kepler-recovery-postgres-restore-test <inventory-sha256>",
            "just kepler-recovery-airflow-retire <approved-retirement-manifest-sha256>",
        ])
        for command in manifest["commands"]:
            self.assertTrue(command.startswith("just "))
            for forbidden in ("ssh", "psql", "dropdb", "rm ", "podman", "docker"):
                self.assertNotIn(forbidden, command)
        self.assertFalse(hasattr(self.module, "execute"))


if __name__ == "__main__":
    unittest.main()
