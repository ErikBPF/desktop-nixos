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
            "provenance_status": "immutable-registry-digest",
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

    def test_stopped_exact_collision_migrates(self):
        result = self.reconcile()
        self.assertEqual(result["manifest"]["status"], "ready")
        self.assertEqual(result["manifest"]["classifications"][0]["classification"], "declared-migrate")

    def test_running_collision_halts(self):
        self.inventory["containers"][0]["state"] = "running"
        self.assertIn("running-collision", self.reconcile()["manifest"]["halt_reasons"])

    def test_exact_stopped_legacy_infra_collision_migrates(self):
        container = self.inventory["containers"][0]
        container["labels"]["com.docker.compose.project"] = "homelab"
        container["labels"]["com.docker.compose.project.working_dir"] = "/fast/homelab"
        container["labels"]["com.docker.compose.project.config_files"] = "infra.yml"
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
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                original_inventory = copy.deepcopy(self.inventory)
                original_desired = copy.deepcopy(self.desired)
                container = self.inventory["containers"][0]
                container["labels"]["com.docker.compose.project"] = "homelab"
                container["labels"]["com.docker.compose.project.working_dir"] = "/fast/homelab"
                container["labels"]["com.docker.compose.project.config_files"] = "infra.yml"
                mutation(container, self.desired["services"][0])
                self.assertEqual(self.reconcile()["manifest"]["status"], "halt")
                self.inventory = original_inventory
                self.desired = original_desired

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
        self.desired["services"][0]["provenance_status"] = "local-provenance-recorded"
        self.desired["services"][0]["mounts"][0]["source"] = "/outside/data"
        reasons = self.reconcile()["manifest"]["halt_reasons"]
        self.assertIn("local-image-or-model-provenance-required", reasons)
        self.assertIn("persistent-mount-outside-snapshot-boundary", reasons)

    def test_local_image_or_model_provenance_record_clears_gap(self):
        self.desired["services"][0]["provenance_status"] = "local-provenance-recorded"
        self.desired["services"][0]["image"] = "kepler/postgres:test"
        self.inventory["containers"][0]["image"] = "kepler/postgres:test"
        self.desired["local_images"] = {"kepler/postgres:test": {
            "observed_image_digest": "sha256:" + "a" * 64,
        }}
        self.assertNotIn("local-image-or-model-provenance-required", self.reconcile()["manifest"]["halt_reasons"])

    def test_unrecorded_model_identity_keeps_local_provenance_halted(self):
        self.desired["services"][0].update({
            "image": "kepler/postgres:test", "model_artifacts": ["postgres-model"],
            "provenance_status": "local-provenance-recorded",
        })
        self.inventory["containers"][0]["image"] = "kepler/postgres:test"
        self.desired["local_images"] = {"kepler/postgres:test": {
            "observed_image_digest": "sha256:" + "a" * 64,
        }}
        self.desired["model_artifacts"] = {"postgres-model": {"status": "identity-required"}}
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
