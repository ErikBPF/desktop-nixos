import copy
import importlib.util
import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
ASSEMBLER = ROOT / "modules/hosts/kepler/_collision_recovery_retirement_evidence.py"
PLANNER = ROOT / "modules/hosts/kepler/_collision_recovery_retirement.py"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/retirement-evidence.json"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RetirementEvidenceAssemblerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.assembler = load(ASSEMBLER, "retirement_evidence")
        cls.retirement = load(PLANNER, "retirement")

    def setUp(self):
        fixture = json.loads(FIXTURE.read_text())
        disposition = fixture["dispositions"]
        containers = []
        for item in disposition["containers"]:
            containers.append({
                "id": item["id"],
                "mounts": [{"source": source} for source in item["mount_retention"]["envelope"]["sources"]],
                "name": item["name"],
                "state": item["state"],
            })
        gitlab_id = "1" * 64
        f5_id = disposition["images"][0]["identity"].removeprefix("sha256:")
        inventory = {
            "containers": containers,
            "images": [
                {"id": gitlab_id, "digests": ["docker.io/gitlab/gitlab-ce@sha256:" + "a" * 64]},
                {"id": f5_id, "digests": []},
            ],
            "networks": [],
            "references": {"images": {"sha256:" + gitlab_id: [], "sha256:" + f5_id: ["f5-tts-server"]}},
            "volumes": [],
        }
        self.inventory = {
            "inventory": inventory,
            "inventory_sha256": self.assembler.digest(inventory),
            "schema": "kepler-collision-inventory-v1",
        }
        records = copy.deepcopy(fixture["proofs"]["retirement_paths"]["envelope"]["paths"])
        for record in records:
            if record["path"] != "/fast/ai-models/f5-tts":
                record.update({"byte_count": None, "device": None, "existence": False, "inode": None, "type": None})
        self.paths = {
            "evidence": records,
            "evidence_sha256": self.assembler.digest(records),
            "schema": "kepler-retirement-path-evidence-envelope-v1",
            "status": "verified",
        }
        self.database = copy.deepcopy(fixture["proofs"]["retained_database_restore"]["envelope"])
        self.database["manifest"]["inventory_sha256"] = self.inventory["inventory_sha256"]
        self.database["manifest_sha256"] = self.assembler.digest(self.database["manifest"])

    def test_assembles_current_image_only_and_absent_families(self):
        evidence = self.assembler.assemble(self.inventory, self.paths, self.database)
        by_family = {item["family"]: item for item in evidence["retired"]}
        self.assertEqual(by_family["gitlab"]["images"], ["sha256:" + "1" * 64])
        self.assertEqual(by_family["gitlab"]["containers"], [])
        self.assertEqual(by_family["gitlab"]["paths"], [])
        for family in ("airflow", "restate"):
            resources = by_family[family]
            self.assertEqual(resources["containers"], [])
            self.assertEqual(resources["paths"], [])
            self.assertEqual(resources["volumes"], [])
            self.assertEqual(resources["images"], [])
        preflight = evidence["proofs"]["retired_preflight"]["envelope"]
        self.assertEqual(preflight["declared_secrets"], [])
        self.assertEqual(preflight["external_credentials"], [])

    def test_output_is_accepted_by_retirement_planner(self):
        evidence = self.assembler.assemble(self.inventory, self.paths, self.database)
        manifest = self.retirement.plan(self.inventory, evidence)
        self.assertEqual(manifest["status"], "ready-for-explicit-hash-bound-approval")
        kinds = [action["kind"] for action in manifest["actions"]]
        self.assertIn("artifact", kinds)
        self.assertIn("image", kinds)

    def test_is_deterministic_and_idempotent_with_absent_retired_resources(self):
        first = self.assembler.assemble(self.inventory, self.paths, self.database)
        second = self.assembler.assemble(copy.deepcopy(self.inventory), copy.deepcopy(self.paths), copy.deepcopy(self.database))
        self.assertEqual(first, second)
        self.retirement.plan(self.inventory, second)

    def test_rejects_input_drift_and_missing_disposition(self):
        changed = copy.deepcopy(self.inventory)
        changed["inventory"]["images"] = []
        with self.assertRaisesRegex(self.assembler.RetirementEvidenceHalt, "inventory SHA-256"):
            self.assembler.assemble(changed, self.paths, self.database)
        changed = copy.deepcopy(self.inventory)
        changed["inventory"]["containers"] = changed["inventory"]["containers"][1:]
        changed["inventory_sha256"] = self.assembler.digest(changed["inventory"])
        database = copy.deepcopy(self.database)
        database["manifest"]["inventory_sha256"] = changed["inventory_sha256"]
        database["manifest_sha256"] = self.assembler.digest(database["manifest"])
        with self.assertRaisesRegex(self.assembler.RetirementEvidenceHalt, "disposition container absent"):
            self.assembler.assemble(changed, self.paths, database)


if __name__ == "__main__":
    unittest.main()
