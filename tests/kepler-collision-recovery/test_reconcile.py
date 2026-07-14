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
        }], "protected_services": [{"container_name": "restate"}]}
        self.inventory = {"containers": [{
            "id": "b" * 64, "image": "registry/postgres", "image_digest": "sha256:" + "a" * 64,
            "image_provenance": "immutable-digest", "labels": self.desired["services"][0]["required_labels"],
            "mounts": [{"source": "/fast/apps/postgres", "destination": "/data", "name": ""}],
            "name": "postgres", "networks": ["infra_default"], "state": "exited",
        }], "datasets": [{"name": "fast", "mountpoint": "/fast"}], "images": [], "volumes": [], "networks": [], "snapshots": [], "references": {"images": {}, "volumes": {}, "networks": {}}}

    def envelope(self, kind, payload):
        return {kind: payload, f"{kind}_sha256": self.module.digest(payload), "schema": f"kepler-collision-{kind}-v1"}

    def reconcile(self):
        return self.module.reconcile(self.envelope("inventory", self.inventory), self.envelope("desired", self.desired), {"desktop-nixos": SHA, "servarr": "2" * 40})

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

    def test_noncollision_and_restate_are_never_actions(self):
        self.inventory["containers"][0]["name"] = "unmanaged"
        self.inventory["containers"].append({**self.inventory["containers"][0], "id": "c" * 64, "name": "restate"})
        items = {item["container"]: item for item in self.reconcile()["manifest"]["classifications"]}
        self.assertEqual(items["unmanaged"]["action"], "none")
        self.assertEqual(items["restate"]["reason"], "restate-protected")

    def test_protected_restate_is_separate_from_active_services(self):
        self.desired["services"].append({**self.desired["services"][0], "container_name": "restate", "service": "restate"})
        with self.assertRaisesRegex(self.module.ReconcileHalt, "protected service.*active"):
            self.reconcile()

    def test_allowlist_selects_only_present_exact_families(self):
        self.inventory["containers"].append({**self.inventory["containers"][0], "id": "c" * 64, "name": "gitlab"})
        self.inventory["containers"].append({**self.inventory["containers"][0], "id": "d" * 64, "name": "gitlab-unknown"})
        manifest = self.reconcile()["manifest"]
        self.assertEqual(manifest["retired_allowlist"], ["airflow", "gitlab"])
        self.assertEqual(manifest["selected_retired"], ["gitlab"])

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
