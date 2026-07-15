import copy
import hashlib
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
PLANNER = ROOT / "modules/hosts/discovery/_stateful-swag-preflight.py"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/inventory.json"


def load_planner():
    spec = importlib.util.spec_from_file_location("swag_preflight", PLANNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SwagPreflightTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.planner = load_planner()

    def setUp(self):
        self.inventory = json.loads(FIXTURE.read_text())

    def plan(self, inventory=None):
        return self.planner.plan(self.inventory if inventory is None else inventory)

    def container(self, name):
        return next(item for item in self.inventory["containers"] if item["name"] == name)

    def assert_halts(self, mutate):
        inventory = copy.deepcopy(self.inventory)
        mutate(inventory)
        with self.assertRaises(self.planner.PreflightHalt):
            self.plan(inventory)

    def test_exact_allowlist_and_phase(self):
        manifest = self.plan()
        self.assertEqual([item["name"] for item in manifest["resources"]], ["swag", "swag-init"])
        self.assertEqual(manifest["phase"], "p1-swag-in-place-adoption")
        self.assertEqual(manifest["mode"], "preflight-only")

    def test_identity_labels_owner_and_state_are_exact(self):
        mutations = [
            lambda i: i["containers"].append(copy.deepcopy(i["containers"][0])),
            lambda i: i["containers"].pop(),
            lambda i: self.container_from(i, "swag").update(name="other"),
            lambda i: self.container_from(i, "swag").update(id="short"),
            lambda i: self.container_from(i, "swag").update(compose_project="foreign"),
            lambda i: self.container_from(i, "swag").update(compose_service="other"),
            lambda i: self.container_from(i, "swag").update(compose_working_dir="/tmp"),
            lambda i: self.container_from(i, "swag").update(state="exited"),
            lambda i: self.container_from(i, "swag-init").update(state="running"),
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                self.assert_halts(mutation)

    @staticmethod
    def container_from(inventory, name):
        return next(item for item in inventory["containers"] if item["name"] == name)

    def test_immutable_refs_and_image_ids_are_required(self):
        for mutation in [
            lambda i: self.container_from(i, "swag").update(image_ref="lscr.io/linuxserver/swag:latest"),
            lambda i: self.container_from(i, "swag-init").update(image_ref="busybox:1.38"),
            lambda i: self.container_from(i, "swag").update(image_id="short"),
        ]:
            self.assert_halts(mutation)

    def test_exact_config_mount_is_required_for_both(self):
        for name in ("swag", "swag-init"):
            for mounts in ([], [{"source": "/wrong", "target": "/config", "type": "bind"}], [{"source": "/home/erik/servarr/machines/discovery/config/swag", "target": "/wrong", "type": "bind"}]):
                with self.subTest(name=name, mounts=mounts):
                    self.assert_halts(lambda i, n=name, m=mounts: self.container_from(i, n).update(mounts=m))

    def test_servarr_commit_render_and_cert_metadata_are_bound(self):
        mutations = [
            lambda i: i["servarr"].update(commit="short"),
            lambda i: i["servarr"].update(render_sha256="short"),
            lambda i: i["certificate"].update(fingerprint_sha256="short"),
            lambda i: i["certificate"].update(sans=[]),
            lambda i: i["certificate"].update(not_after="unknown"),
        ]
        for mutation in mutations:
            self.assert_halts(mutation)

    def test_evidence_paths_are_exact_and_collision_free(self):
        self.assert_halts(lambda i: i["evidence_collisions"].append(i["evidence"]["ledger"]))
        self.assert_halts(lambda i: i["evidence"].update(ledger="/tmp/ledger.json"))
        self.assert_halts(lambda i: i["evidence"].update(result=i["evidence"]["ledger"]))

    def test_deterministic_value_free_and_sha_bound(self):
        first = self.plan()
        second = self.plan(json.loads(json.dumps(self.inventory, sort_keys=True)))
        self.assertEqual(first, second)
        self.assertEqual(first["inventory_sha256"], self.planner.inventory_hash(self.inventory))
        encoded = self.planner.canonical(first)
        envelope = self.planner.envelope(first)
        self.assertEqual(envelope["manifest_sha256"], hashlib.sha256(encoded).hexdigest())
        rendered = json.dumps(envelope, sort_keys=True).lower()
        for token in ("secret_value", "token_value", "password", "credential", "environment"):
            self.assertNotIn(token, rendered)

    def test_value_fields_are_rejected_recursively(self):
        for key in ("environment", "env", "secret_value", "token", "password", "credential"):
            self.assert_halts(lambda i, k=key: i.update({k: None}))

    def test_inventory_drift_invalidates_authorization(self):
        envelope = self.planner.envelope(self.plan())
        self.planner.verify(self.inventory, envelope)
        changed = copy.deepcopy(self.inventory)
        changed["certificate"]["not_after"] = "2026-10-13T00:00:00Z"
        with self.assertRaises(self.planner.InventoryDrift):
            self.planner.verify(changed, envelope)
        tampered = copy.deepcopy(envelope)
        tampered["manifest"]["mode"] = "execute"
        with self.assertRaises(self.planner.InventoryDrift):
            self.planner.verify(self.inventory, tampered)

    def test_no_destructive_tokens_or_commands(self):
        rendered = json.dumps(self.plan(), sort_keys=True).lower()
        for token in ("docker rm", "volume rm", "prune", "zfs destroy", "btrfs subvolume delete", "rm -r", "execute"):
            self.assertNotIn(token, rendered)
        self.assertNotIn("commands", self.plan())


if __name__ == "__main__":
    unittest.main()
