import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).parents[2]
SCRIPT = ROOT / "modules/hosts/kepler/_collision_recovery_reconcile.py"
SHA = "1" * 40


def load_module():
    spec = importlib.util.spec_from_file_location("reconcile", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReconcileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.desired = {"schema": "kepler-collision-desired-v1", "services": [{
            "container_name": "postgres", "digest_status": "immutable-registry-digest",
            "image": "registry/postgres@sha256:" + "a" * 64,
            "mounts": [{"source": "/fast/apps/postgres", "target": "/data", "type": "bind"}],
            "networks": ["infra_default"], "project": "infra",
            "provenance_status": {},
            "required_labels": {"com.docker.compose.project": "infra", "com.docker.compose.service": "postgres"},
            "service": "postgres",
        }], "protected_services": []}
        self.inventory = {"containers": [{
            "id": "b" * 64, "image": "registry/postgres", "image_digest": "sha256:" + "a" * 64,
            "image_provenance": "immutable-digest", "labels": self.desired["services"][0]["required_labels"],
            "mounts": [{"source": "/fast/apps/postgres", "destination": "/data", "name": ""}],
            "name": "postgres", "networks": ["infra_default"], "state": "exited",
        }], "datasets": [{"name": "fast", "mountpoint": "/fast"}], "images": [], "volumes": [], "networks": [], "snapshots": [], "references": {"images": {}, "volumes": {}, "networks": {}}}

    def envelope(self, kind, payload):
        return {kind: payload, f"{kind}_sha256": self.module.digest(payload), "schema": f"kepler-collision-{kind}-v1"}

    def reconcile(self, mode="migration"):
        return self.module.reconcile(self.envelope("inventory", self.inventory), self.envelope("desired", self.desired), {"desktop-nixos": SHA, "servarr": "2" * 40}, mode=mode)

    def make_legacy(self):
        container = self.inventory["containers"][0]
        container["labels"]["com.docker.compose.project"] = "homelab"
        container["labels"]["com.docker.compose.project.working_dir"] = "/fast/homelab"
        container["labels"]["com.docker.compose.project.config_files"] = "infra.yml"
        self.desired["legacy_images"] = {"postgres": {
            "image": "docker.io/registry/postgres",
            "image_digest": "sha256:" + "a" * 64,
        }}

    def test_stopped_exact_collision_migrates(self):
        result = self.reconcile()
        self.assertEqual(result["manifest"]["status"], "ready")
        self.assertEqual(result["manifest"]["classifications"][0]["classification"], "declared-migrate")

    def test_running_collision_halts(self):
        self.inventory["containers"][0]["state"] = "running"
        self.assertIn("running-collision", self.reconcile()["manifest"]["halt_reasons"])

    def test_post_recovery_audit_marks_exact_running_desired_container_converged(self):
        self.inventory["containers"][0]["state"] = "running"
        first = self.reconcile(mode="post-recovery-audit")
        second = self.reconcile(mode="post-recovery-audit")
        item = first["manifest"]["classifications"][0]
        self.assertEqual(first, second)
        self.assertEqual(first["manifest_sha256"], self.module.digest(first["manifest"]))
        self.assertEqual(first["manifest"]["mode"], "post-recovery-audit")
        self.assertEqual(first["manifest"]["status"], "converged")
        self.assertEqual((item["action"], item["classification"], item["reason"]),
                         ("none", "converged", "exact-running-desired"))

    def test_post_recovery_audit_still_halts_on_runtime_drift(self):
        self.inventory["containers"][0]["state"] = "running"
        self.inventory["containers"][0]["networks"] = ["foreign"]
        result = self.reconcile(mode="post-recovery-audit")["manifest"]
        self.assertEqual(result["status"], "halt")
        self.assertIn("declared-runtime-mismatch", result["halt_reasons"])

    def test_post_recovery_audit_halts_when_desired_container_is_absent(self):
        self.inventory["containers"] = []
        result = self.reconcile(mode="post-recovery-audit")["manifest"]
        self.assertEqual(result["status"], "halt")
        self.assertIn("desired-container-absent", result["halt_reasons"])

    def test_post_recovery_audit_halts_when_exact_retired_resource_remains(self):
        self.inventory["containers"][0]["state"] = "running"
        self.inventory["containers"].append({
            **self.inventory["containers"][0], "id": "c" * 64, "name": "restate",
            "labels": {"com.docker.compose.project": "restate", "com.docker.compose.service": "restate"},
        })
        result = self.reconcile(mode="post-recovery-audit")["manifest"]
        retired = next(item for item in result["classifications"] if item["container"] == "restate")
        self.assertEqual(result["status"], "halt")
        self.assertIn("retired-resource-still-present", result["halt_reasons"])
        self.assertEqual((retired["action"], retired["classification"], retired["reason"]),
                         ("halt", "halt", "retired-resource-still-present"))

    def test_post_recovery_audit_fail_closed_matrix(self):
        mutations = (
            (lambda c: c.update({"state": "exited"}), "desired-container-not-running"),
            (lambda c: c["labels"].clear(), "missing-compose-labels"),
            (lambda c: c["labels"].update({"com.docker.compose.project": "foreign"}), "foreign-compose-project"),
            (lambda c: c["labels"].update({"com.docker.compose.service": "foreign"}), "foreign-compose-service"),
            (lambda c: c["mounts"][0].update({"source": "/wrong"}), "declared-runtime-mismatch"),
            (lambda c: c["mounts"][0].update({"read_only": True}), "declared-runtime-mismatch"),
            (lambda c: c.update({"image_digest": "sha256:" + "b" * 64}), "immutable-registry-digest-required"),
        )
        for mutation, reason in mutations:
            with self.subTest(reason=reason):
                original_inventory = copy.deepcopy(self.inventory)
                original_desired = copy.deepcopy(self.desired)
                self.inventory["containers"][0]["state"] = "running"
                mutation(self.inventory["containers"][0])
                self.assertIn(reason, self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"])
                self.inventory = original_inventory
                self.desired = original_desired

    def test_post_recovery_audit_halts_on_local_model_coverage_and_unknown_owner(self):
        container = self.inventory["containers"][0]
        container["state"] = "running"
        desired_item = self.desired["services"][0]
        desired_item["digest_status"] = "local-provenance-recorded"
        desired_item["provenance_status"] = {
            "local_image": "kepler/postgres:test", "model_artifacts": ["postgres-model"],
        }
        desired_item["image"] = "kepler/postgres:test"
        desired_item["mounts"][0]["source"] = "/outside/data"
        container["image"] = "kepler/postgres:test"
        container["mounts"][0]["source"] = "/outside/data"
        self.desired["local_images"] = {}
        self.desired["model_artifacts"] = {"postgres-model": {"status": "identity-required"}}
        self.inventory["containers"].append({
            **container, "id": "d" * 64, "name": "unknown", "labels": {},
        })
        reasons = self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"]
        self.assertIn("local-image-or-model-provenance-required", reasons)
        self.assertIn("persistent-mount-outside-snapshot-boundary", reasons)
        self.assertIn("unknown-owner", reasons)

    def test_post_recovery_audit_accepts_runtime_registry_ref_without_desired_tag(self):
        item = self.desired["services"][0]
        item["image"] = "rhasspy/wyoming-piper:2.2.2@sha256:" + "a" * 64
        container = self.inventory["containers"][0]
        container.update({
            "state": "running",
            "image": "docker.io/rhasspy/wyoming-piper@sha256:" + "a" * 64,
        })
        self.assertEqual(self.reconcile(mode="post-recovery-audit")["manifest"]["status"], "converged")

    def test_post_recovery_audit_resolves_relative_bind_against_compose_working_dir(self):
        item = self.desired["services"][0]
        item["mounts"][0]["source"] = "./scripts/provision-db.sql"
        item["mounts"][0]["read_only"] = True
        container = self.inventory["containers"][0]
        container["state"] = "running"
        container["labels"] = copy.deepcopy(container["labels"])
        container["labels"]["com.docker.compose.project.working_dir"] = "/home/erik/servarr/machines/kepler"
        container["mounts"][0]["source"] = "/home/erik/servarr/machines/kepler/scripts/provision-db.sql"
        container["mounts"][0]["read_only"] = True
        self.assertEqual(self.reconcile(mode="post-recovery-audit")["manifest"]["status"], "converged")
        container["mounts"][0]["source"] = "/tmp/scripts/provision-db.sql"
        self.assertIn("declared-runtime-mismatch", self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"])
        container["labels"]["com.docker.compose.project.working_dir"] = "/tmp/checkout"
        container["mounts"][0]["source"] = "/tmp/checkout/scripts/provision-db.sql"
        self.assertIn("declared-runtime-mismatch", self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"])

    def test_post_recovery_audit_resolves_compose_named_volume_and_coverage(self):
        item = self.desired["services"][0]
        item.update({"container_name": "redis", "service": "redis"})
        item["required_labels"]["com.docker.compose.service"] = "redis"
        item["mounts"] = [{"source": "redis_data", "target": "/data", "type": "volume"}]
        container = self.inventory["containers"][0]
        container["name"] = "redis"
        container["labels"]["com.docker.compose.service"] = "redis"
        container["state"] = "running"
        mountpoint = "/var/lib/containers/storage/volumes/infra_redis_data/_data"
        container["mounts"] = [{
            "source": mountpoint, "destination": "/data", "name": "infra_redis_data",
        }]
        self.inventory["volumes"] = [{"name": "infra_redis_data", "mountpoint": mountpoint}]
        result = self.reconcile(mode="post-recovery-audit")["manifest"]
        self.assertEqual(result["status"], "converged")
        self.assertFalse(result["persistent_coverage_gaps"])
        container["mounts"][0]["source"] = "/wrong/infra_redis_data/_data"
        self.assertIn("declared-runtime-mismatch", self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"])

    def test_post_recovery_audit_nonredis_named_volume_outside_dataset_halts(self):
        item = self.desired["services"][0]
        item["mounts"] = [{"source": "data", "target": "/data", "type": "volume"}]
        container = self.inventory["containers"][0]
        container["state"] = "running"
        mountpoint = "/var/lib/containers/storage/volumes/infra_data/_data"
        container["mounts"] = [{"source": mountpoint, "destination": "/data", "name": "infra_data"}]
        self.inventory["volumes"] = [{"name": "infra_data", "mountpoint": mountpoint}]
        self.assertIn(
            "persistent-mount-outside-snapshot-boundary",
            self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"],
        )

    def test_post_recovery_audit_relative_bind_requires_exact_working_dir_and_absolute_runtime(self):
        item = self.desired["services"][0]
        item["mounts"][0].update({"source": "./scripts/provision-db.sql", "read_only": True})
        container = self.inventory["containers"][0]
        container["state"] = "running"
        container["labels"] = copy.deepcopy(container["labels"])
        container["mounts"][0].update({"source": "./scripts/provision-db.sql", "read_only": True})
        for working_dir in ("", "/wrong"):
            with self.subTest(working_dir=working_dir):
                if working_dir:
                    container["labels"]["com.docker.compose.project.working_dir"] = working_dir
                else:
                    container["labels"].pop("com.docker.compose.project.working_dir", None)
                self.assertIn(
                    "declared-runtime-mismatch",
                    self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"],
                )
        container["labels"]["com.docker.compose.project.working_dir"] = "/home/erik/servarr/machines/kepler"
        self.assertIn(
            "declared-runtime-mismatch",
            self.reconcile(mode="post-recovery-audit")["manifest"]["halt_reasons"],
        )

    def test_empty_or_duplicate_inventory_volume_names_fail_closed(self):
        valid = {"name": "infra_data", "mountpoint": "/fast/infra_data"}
        for volumes in ([{**valid, "name": ""}], [valid, copy.deepcopy(valid)]):
            with self.subTest(volumes=volumes):
                self.inventory["volumes"] = volumes
                with self.assertRaisesRegex(self.module.ReconcileHalt, "volumes require unique non-empty names"):
                    self.reconcile(mode="post-recovery-audit")

    def test_duplicate_or_empty_inventory_names_fail_closed_independent_of_order(self):
        duplicate = {**copy.deepcopy(self.inventory["containers"][0]), "id": "c" * 64}
        for containers in (
            [self.inventory["containers"][0], duplicate],
            [duplicate, self.inventory["containers"][0]],
        ):
            with self.subTest(order=[item["id"] for item in containers]):
                self.inventory["containers"] = containers
                with self.assertRaisesRegex(self.module.ReconcileHalt, "unique non-empty names"):
                    self.reconcile(mode="post-recovery-audit")
        self.inventory["containers"] = [{**duplicate, "name": ""}]
        with self.assertRaisesRegex(self.module.ReconcileHalt, "unique non-empty names"):
            self.reconcile(mode="post-recovery-audit")

    def test_exact_stopped_legacy_infra_collision_migrates(self):
        self.make_legacy()
        self.desired["services"][0]["image"] = "registry/replacement@sha256:" + "b" * 64
        item = self.reconcile()["manifest"]["classifications"][0]
        self.assertEqual(item["action"], "migrate")
        self.assertEqual(item["reason"], "legacy-declared-migrate")

    def test_legacy_adoption_rejects_noninfra_running_unlabeled_and_metadata_mismatch(self):
        mutations = (
            lambda c, d: c.update({"state": "running"}),
            lambda c, d: c["labels"].clear(),
            lambda c, d: d.update({"project": "ai-serving"}),
            lambda c, d: c["labels"].update({"com.docker.compose.project.working_dir": "/wrong"}),
            lambda c, d: c["labels"].update({"com.docker.compose.project.config_files": "other.yml"}),
            lambda c, d: c["mounts"][0].update({"source": "/wrong"}),
            lambda c, d: c.update({"image_digest": "sha256:" + "b" * 64}),
            lambda c, d: self.desired["legacy_images"]["postgres"].update({"image": "other/image"}),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                original_inventory = copy.deepcopy(self.inventory)
                original_desired = copy.deepcopy(self.desired)
                self.make_legacy()
                container = self.inventory["containers"][0]
                mutation(container, self.desired["services"][0])
                self.assertEqual(self.reconcile()["manifest"]["status"], "halt")
                self.inventory = original_inventory
                self.desired = original_desired

    def test_docker_image_reference_normalization_is_narrow(self):
        normalize = self.module._normalized_image_ref
        self.assertEqual(normalize("postgres"), "docker.io/library/postgres")
        self.assertEqual(normalize("kepler/docs:latest"), "docker.io/kepler/docs:latest")
        self.assertEqual(normalize("rhasspy/wyoming-piper"), "docker.io/rhasspy/wyoming-piper")
        self.assertEqual(normalize("utkuozdemir/nvidia_gpu_exporter"), "docker.io/utkuozdemir/nvidia_gpu_exporter")
        self.assertEqual(normalize("ghcr.io/example/image"), "ghcr.io/example/image")

    def test_reviewed_legacy_postgres_mount_mapping_is_recorded(self):
        self.make_legacy()
        runtime_mount = copy.deepcopy(self.inventory["containers"][0]["mounts"][0])
        self.desired["services"][0]["mounts"][0]["source"] = "/fast/postgres"
        desired_mount = copy.deepcopy(self.desired["services"][0]["mounts"][0])
        self.desired["legacy_mounts"] = {"postgres": [{
            "runtime": runtime_mount, "desired": desired_mount,
        }]}
        item = self.reconcile()["manifest"]["classifications"][0]
        self.assertEqual(item["reason"], "legacy-declared-migrate")
        self.assertEqual(item["migration_mounts"], self.desired["legacy_mounts"]["postgres"])

    def test_unreviewed_or_inexact_legacy_mount_mapping_halts(self):
        self.make_legacy()
        runtime_mount = copy.deepcopy(self.inventory["containers"][0]["mounts"][0])
        self.desired["services"][0]["mounts"][0]["source"] = "/fast/postgres"
        self.desired["legacy_mounts"] = {"postgres": [{
            "runtime": runtime_mount,
            "desired": {"source": "/wrong", "target": "/data", "type": "bind"},
        }]}
        self.assertEqual(self.reconcile()["manifest"]["status"], "halt")

    def test_missing_foreign_and_mount_mismatch_halt_with_diffs(self):
        for mutation, reason in (
            (lambda c: c["labels"].clear(), "missing-compose-labels"),
            (lambda c: c["labels"].update({"com.docker.compose.project": "foreign"}), "foreign-compose-project"),
            (lambda c: c["mounts"][0].update({"source": "/wrong"}), "declared-runtime-mismatch"),
        ):
            original = copy.deepcopy(self.inventory)
            mutation(self.inventory["containers"][0])
            item = self.reconcile()["manifest"]["classifications"][0]
            self.assertEqual(item["reason"], reason)
            if reason.endswith("mismatch"):
                self.assertTrue(item["field_diffs"])
            self.inventory = original

    def test_undeclared_container_halts_while_restate_retires(self):
        self.inventory["containers"][0]["name"] = "unmanaged"
        self.inventory["containers"].append({**self.inventory["containers"][0], "id": "c" * 64, "name": "restate", "labels": {"com.docker.compose.project": "restate", "com.docker.compose.service": "restate"}})
        items = {item["container"]: item for item in self.reconcile()["manifest"]["classifications"]}
        self.assertEqual(items["unmanaged"]["action"], "halt")
        self.assertEqual(items["unmanaged"]["reason"], "unknown-owner")
        self.assertEqual((items["restate"]["classification"], items["restate"]["action"]), ("retired-wipe", "retire"))

    def test_restate_must_not_remain_declarative(self):
        self.desired["services"].append({**self.desired["services"][0], "container_name": "restate", "service": "restate"})
        with self.assertRaisesRegex(self.module.ReconcileHalt, "retired service.*active"):
            self.reconcile()

    def test_allowlist_selects_only_present_exact_families(self):
        self.inventory["containers"].append({
            **self.inventory["containers"][0], "id": "c" * 64, "name": "gitlab",
            "labels": {"com.docker.compose.project": "gitlab", "com.docker.compose.service": "gitlab"},
        })
        self.inventory["containers"].append({**self.inventory["containers"][0], "id": "d" * 64, "name": "gitlab-unknown"})
        manifest = self.reconcile()["manifest"]
        self.assertEqual(manifest["retired_allowlist"], ["airflow", "gitlab", "restate"])
        self.assertEqual(manifest["selected_retired"], ["gitlab"])
        selected = next(item for item in manifest["classifications"] if item["container"] == "gitlab")
        self.assertEqual((selected["classification"], selected["action"]), ("retired-wipe", "retire"))
        unknown = next(item for item in manifest["classifications"] if item["container"] == "gitlab-unknown")
        self.assertEqual((unknown["classification"], unknown["action"]), ("halt", "halt"))

    def test_retired_name_requires_exact_project_and_service_ownership(self):
        for labels in (
            {"com.docker.compose.project": "foreign", "com.docker.compose.service": "gitlab"},
            {"com.docker.compose.project": "gitlab", "com.docker.compose.service": "unknown"},
        ):
            with self.subTest(labels=labels):
                self.inventory["containers"][0].update({"name": "gitlab", "labels": labels})
                item = self.reconcile()["manifest"]["classifications"][0]
                self.assertEqual((item["classification"], item["action"]), ("halt", "halt"))

    def test_runtime_mount_type_and_read_only_are_exact_identity(self):
        self.inventory["containers"][0]["mounts"][0].update({"type": "volume", "read_only": False})
        self.assertIn("declared-runtime-mismatch", self.reconcile()["manifest"]["halt_reasons"])
        self.inventory["containers"][0]["mounts"][0]["type"] = "bind"
        self.inventory["containers"][0]["mounts"][0]["read_only"] = True
        self.assertIn("declared-runtime-mismatch", self.reconcile()["manifest"]["halt_reasons"])

    def test_provenance_and_coverage_gaps_halt(self):
        self.desired["services"][0]["digest_status"] = "local-provenance-recorded"
        self.desired["services"][0]["provenance_status"] = {"local_image": "kepler/postgres:test"}
        self.desired["services"][0]["mounts"][0]["source"] = "/outside/data"
        reasons = self.reconcile()["manifest"]["halt_reasons"]
        self.assertIn("local-image-or-model-provenance-required", reasons)
        self.assertIn("persistent-mount-outside-snapshot-boundary", reasons)

    def test_read_only_mount_is_identity_but_not_persistent_coverage(self):
        self.desired["services"][0]["mounts"].append({
            "read_only": True, "source": "/outside/config", "target": "/config", "type": "bind",
        })
        self.inventory["containers"][0]["mounts"].append({
            "read_only": True, "source": "/outside/config", "destination": "/config", "name": "",
        })
        result = self.reconcile()["manifest"]
        self.assertFalse(result["persistent_coverage_gaps"])
        self.inventory["containers"][0]["mounts"][-1]["read_only"] = False
        self.assertIn("declared-runtime-mismatch", self.reconcile()["manifest"]["halt_reasons"])

    def test_unverified_redis_named_volume_remains_coverage_gap(self):
        self.desired["services"][0]["mounts"] = [{
            "source": "redis_data", "target": "/data", "type": "volume",
        }]
        self.inventory["containers"][0]["mounts"] = [{
            "source": "redis_data", "destination": "/data", "name": "redis_data",
        }]
        self.assertIn("persistent-mount-outside-snapshot-boundary", self.reconcile()["manifest"]["halt_reasons"])

    def test_local_image_or_model_provenance_record_clears_gap(self):
        self.desired["services"][0]["digest_status"] = "local-provenance-recorded"
        self.desired["services"][0]["provenance_status"] = {"local_image": "kepler/postgres:test"}
        self.desired["services"][0]["image"] = "kepler/postgres:test"
        self.inventory["containers"][0]["image"] = "kepler/postgres:test"
        self.desired["local_images"] = {"kepler/postgres:test": {
            "observed_image_digest": "sha256:" + "a" * 64,
        }}
        self.assertNotIn("local-image-or-model-provenance-required", self.reconcile()["manifest"]["halt_reasons"])

    def test_unrecorded_model_identity_keeps_local_provenance_halted(self):
        self.desired["services"][0].update({
            "digest_status": "local-provenance-recorded", "image": "kepler/postgres:test",
            "provenance_status": {"local_image": "kepler/postgres:test", "model_artifacts": ["postgres-model"]},
        })
        self.inventory["containers"][0]["image"] = "kepler/postgres:test"
        self.desired["local_images"] = {"kepler/postgres:test": {
            "observed_image_digest": "sha256:" + "a" * 64,
        }}
        self.desired["model_artifacts"] = {"postgres-model": {"status": "identity-required"}}
        self.assertIn("local-image-or-model-provenance-required", self.reconcile()["manifest"]["halt_reasons"])

    def test_registry_image_with_unrecorded_model_identity_halts(self):
        self.desired["services"][0]["provenance_status"] = {
            "local_image": None, "model_artifacts": ["postgres-model"],
        }
        self.desired["model_artifacts"] = {"postgres-model": {
            "algorithm": "kepler-tree-sha256-v1", "byte_count": 10, "entry_count": 1,
            "root": "/fast/models/postgres", "sha256": "b" * 64, "status": "identity-required",
        }}
        self.assertIn("local-image-or-model-provenance-required", self.reconcile()["manifest"]["halt_reasons"])

    def test_registry_image_with_exact_recorded_model_identity_passes(self):
        self.desired["services"][0]["provenance_status"] = {
            "local_image": None, "model_artifacts": ["postgres-model"],
        }
        self.desired["model_artifacts"] = {"postgres-model": {
            "algorithm": "kepler-tree-sha256-v1", "byte_count": 10, "entry_count": 1,
            "root": "/fast/models/postgres", "sha256": "b" * 64, "status": "identity-recorded",
        }}
        self.assertNotIn("local-image-or-model-provenance-required", self.reconcile()["manifest"]["halt_reasons"])

    def test_model_identity_missing_extra_or_malformed_fields_halts(self):
        self.desired["services"][0]["provenance_status"] = {
            "local_image": None, "model_artifacts": ["postgres-model"],
        }
        valid = {
            "algorithm": "kepler-tree-sha256-v1", "byte_count": 10, "entry_count": 1,
            "root": "/fast/models/postgres", "sha256": "b" * 64, "status": "identity-recorded",
        }
        for artifact in ({}, {**valid, "extra": "forbidden"}, {**valid, "sha256": "bad"}):
            with self.subTest(artifact=artifact):
                self.desired["model_artifacts"] = {"postgres-model": artifact}
                self.assertIn("local-image-or-model-provenance-required", self.reconcile()["manifest"]["halt_reasons"])

    def test_hash_binding_drift_and_determinism(self):
        first = self.reconcile()
        self.assertEqual(first, self.reconcile())
        self.assertEqual(first["manifest_sha256"], self.module.digest(first["manifest"]))
        envelope = self.envelope("inventory", self.inventory)
        envelope["inventory"]["containers"][0]["state"] = "running"
        with self.assertRaisesRegex(self.module.ReconcileHalt, "SHA-256 mismatch"):
            self.module.reconcile(envelope, self.envelope("desired", self.desired), {"repo": SHA})

    def test_value_free_and_no_commands(self):
        rendered = json.dumps(self.reconcile(), sort_keys=True)
        for forbidden in ("command", "execute", "prune", "destroy", "rm -rf", "secret_value"):
            self.assertNotIn(forbidden, rendered)


if __name__ == "__main__":
    unittest.main()
