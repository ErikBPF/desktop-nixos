import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_redis_backup.py"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/redis-backup-inventory.json"


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def load_module():
    spec = importlib.util.spec_from_file_location("redis_backup", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RedisBackupEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.envelope = json.loads(FIXTURE.read_text())
        self.bind()

    def bind(self):
        self.envelope["inventory_sha256"] = hashlib.sha256(
            canonical(self.envelope["inventory"])
        ).hexdigest()

    def plan(self, expected=None, quiesce_approval=None):
        return self.module.plan(
            self.envelope,
            expected or self.envelope["inventory_sha256"],
            quiesce_approval=quiesce_approval,
        )

    def approval(self):
        container = self.envelope["inventory"]["containers"][0]
        quiesce_manifest = {
            "inventory_sha256": self.envelope["inventory_sha256"],
            "manifest": {
                "inventory_sha256": self.envelope["inventory_sha256"],
                "mode": "dry-run-only",
                "stacks": [{"containers": [container["name"]], "stack": "infra"}],
                "status": "ready-for-separate-hash-bound-approval",
            },
            "schema": "kepler-collision-quiesce-manifest-v1",
        }
        quiesce_manifest["manifest_sha256"] = self.module.digest(quiesce_manifest["manifest"])
        approval = {
            "containers": [{"id": container["id"], "name": container["name"]}],
            "inventory_sha256": self.envelope["inventory_sha256"],
            "quiesce_manifest": quiesce_manifest,
        }
        return {
            "approval": approval,
            "approval_sha256": self.module.digest(approval),
            "schema": "kepler-collision-quiesce-approval-v1",
        }

    def test_binds_exact_legacy_volume_and_distinguishes_declared_target(self):
        manifest = self.plan()["manifest"]
        self.assertEqual(manifest["source_volume"], {
            "driver": "local",
            "mountpoint": "/var/lib/containers/storage/volumes/homelab_redis_data/_data",
            "name": "homelab_redis_data",
            "owner_project": "homelab",
            "references": ["redis"],
        })
        self.assertEqual(manifest["declared_target_volume"], {
            "name": "infra_redis_data", "owner_project": "infra"
        })
        self.assertEqual(manifest["source_container"], {
            "id": "a" * 64,
            "mount_destination": "/data",
            "name": "redis",
            "project": "homelab",
            "service": "redis",
            "state": "exited",
        })

    def test_running_source_requires_matching_quiesce_approval(self):
        self.envelope["inventory"]["containers"][0]["state"] = "running"
        self.bind()
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "running Redis requires approved quiesce binding"):
            self.plan()
        approval = self.approval()
        manifest = self.plan(quiesce_approval=approval)["manifest"]
        self.assertEqual(manifest["quiesce_approval_sha256"], approval["approval_sha256"])

    def test_rejects_unbound_or_drifted_quiesce_approval(self):
        self.envelope["inventory"]["containers"][0]["state"] = "running"
        self.bind()
        approval = self.approval()
        approval["approval"]["containers"][0]["id"] = "d" * 64
        approval["approval_sha256"] = self.module.digest(approval["approval"])
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "container binding"):
            self.plan(quiesce_approval=approval)
        approval = self.approval()
        approval["approval"]["inventory_sha256"] = "e" * 64
        approval["approval_sha256"] = self.module.digest(approval["approval"])
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "inventory binding"):
            self.plan(quiesce_approval=approval)

    def test_rejects_declared_only_tampered_or_nonincluding_quiesce_manifest(self):
        self.envelope["inventory"]["containers"][0]["state"] = "running"
        self.bind()
        approval = self.approval()
        approval["approval"]["quiesce_manifest"] = {"manifest_sha256": "c" * 64}
        approval["approval_sha256"] = self.module.digest(approval["approval"])
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "quiesce manifest envelope"):
            self.plan(quiesce_approval=approval)
        approval = self.approval()
        approval["approval"]["quiesce_manifest"]["manifest"]["stacks"][0]["containers"] = []
        approval["approval"]["quiesce_manifest"]["manifest_sha256"] = self.module.digest(
            approval["approval"]["quiesce_manifest"]["manifest"]
        )
        approval["approval_sha256"] = self.module.digest(approval["approval"])
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "does not include Redis"):
            self.plan(quiesce_approval=approval)
        approval = self.approval()
        approval["approval"]["quiesce_manifest"]["manifest"]["stacks"][0]["stack"] = "other"
        approval["approval"]["quiesce_manifest"]["manifest_sha256"] = self.module.digest(
            approval["approval"]["quiesce_manifest"]["manifest"]
        )
        approval["approval_sha256"] = self.module.digest(approval["approval"])
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "infra stack"):
            self.plan(quiesce_approval=approval)

    def test_only_exited_state_proceeds_without_quiesce(self):
        for state in ("created", "dead", "removing", "unknown"):
            with self.subTest(state=state):
                self.envelope["inventory"]["containers"][0]["state"] = state
                self.bind()
                with self.assertRaisesRegex(self.module.RedisBackupHalt, "must be exactly exited"):
                    self.plan()

    def test_rejects_container_mount_mismatch(self):
        self.envelope["inventory"]["containers"][0]["mounts"][0]["name"] = "infra_redis_data"
        self.bind()
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "source mount mismatch"):
            self.plan()

    def test_orders_save_checksum_disposable_restore_and_compare(self):
        result = self.plan()
        manifest = result["manifest"]
        self.assertEqual([action["kind"] for action in manifest["actions"]], [
            "force-save", "copy-backup", "sha256", "create-disposable-restore",
            "restore-backup", "compare-logical-digest", "remove-disposable-restore",
        ])
        root = f"/fast/backups/kepler-collision-k1/redis/{self.envelope['inventory_sha256']}"
        self.assertEqual(manifest["backup_artifact"], f"{root}/dump.rdb")
        self.assertEqual(manifest["checksum_artifact"], f"{root}/dump.rdb.sha256")
        self.assertEqual(manifest["comparison_artifact"], f"{root}/restore-compare.json")
        self.assertEqual(manifest["snapshot_boundary"], "/fast")

    def test_is_deterministic_value_free_and_hash_bound(self):
        first = self.plan()
        self.assertEqual(first, self.plan())
        self.assertEqual(first["manifest_sha256"], self.module.digest(first["manifest"]))
        rendered = json.dumps(first, sort_keys=True).lower()
        for forbidden in ("password", "token", "secret", "redis_url", "environment"):
            self.assertNotIn(forbidden, rendered)

    def test_rejects_inventory_drift_and_tampering(self):
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "inventory drift"):
            self.plan("f" * 64)
        self.envelope["inventory"]["datasets"] = []
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "SHA-256 mismatch"):
            self.plan()

    def test_rejects_missing_ambiguous_or_wrongly_owned_source(self):
        cases = []
        missing = copy.deepcopy(self.envelope)
        missing["inventory"]["volumes"] = missing["inventory"]["volumes"][1:]
        cases.append(missing)
        duplicate = copy.deepcopy(self.envelope)
        duplicate["inventory"]["volumes"].append(copy.deepcopy(duplicate["inventory"]["volumes"][0]))
        cases.append(duplicate)
        wrong_owner = copy.deepcopy(self.envelope)
        wrong_owner["inventory"]["volumes"][0]["labels"]["com.docker.compose.project"] = "infra"
        cases.append(wrong_owner)
        for item in cases:
            with self.subTest(item=item):
                item["inventory_sha256"] = self.module.digest(item["inventory"])
                with self.assertRaises(self.module.RedisBackupHalt):
                    self.module.plan(item, item["inventory_sha256"])

    def test_rejects_source_already_inside_boundary_and_target_ownership_mismatch(self):
        self.envelope["inventory"]["volumes"][0]["mountpoint"] = "/fast/redis"
        self.envelope["inventory"]["containers"][0]["mounts"][0]["source"] = "/fast/redis"
        self.bind()
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "already inside snapshot boundary"):
            self.plan()
        self.setUp()
        self.envelope["inventory"]["volumes"][1]["labels"]["com.docker.compose.project"] = "homelab"
        self.bind()
        with self.assertRaisesRegex(self.module.RedisBackupHalt, "target volume ownership"):
            self.plan()

    def test_records_abort_rollback_and_no_execute_api(self):
        manifest = self.plan()["manifest"]
        self.assertFalse(manifest["execution_supported"])
        self.assertEqual(manifest["mode"], "dry-run-only")
        self.assertEqual(manifest["abort_boundary"], "before-any-action-on-inventory-drift-or-failed-precondition")
        self.assertEqual(manifest["rollback_boundary"], "source-volume-remains-authoritative-until-verified-restore-compare")
        self.assertFalse(hasattr(self.module, "execute"))


if __name__ == "__main__":
    unittest.main()
