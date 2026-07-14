import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "modules/hosts/kepler/_collision_recovery_inventory.py"
REMOTE = ROOT / "modules/hosts/kepler/_collision_recovery_remote.sh"
FIXTURE = pathlib.Path(__file__).parent / "fixtures/k1-source.json"


def load_collector():
    spec = importlib.util.spec_from_file_location("inventory", COLLECTOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class InventoryCollectorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.collector = load_collector()

    def test_fixture_is_deterministic_value_free_and_hash_bound(self):
        source = json.loads(FIXTURE.read_text())
        first = self.collector.collect_fixture(source)
        second = self.collector.collect_fixture(json.loads(json.dumps(source, sort_keys=True)))
        self.assertEqual(first, second)
        self.assertEqual(first["schema"], "kepler-collision-inventory-v1")
        self.assertRegex(first["inventory_sha256"], r"^[0-9a-f]{64}$")
        rendered = json.dumps(first, sort_keys=True).lower()
        for forbidden in ("environment", "env", "secret_value", "token_value"):
            self.assertNotIn(f'"{forbidden}"', rendered)

    def test_normalizes_only_approved_container_metadata(self):
        result = self.collector.collect_fixture(json.loads(FIXTURE.read_text()))
        container = result["inventory"]["containers"][0]
        self.assertEqual(set(container), {
            "id", "name", "state", "image", "image_digest", "image_provenance", "labels", "mounts", "networks"
        })
        self.assertEqual(container["labels"], {
            "com.docker.compose.project": "infra",
            "com.docker.compose.service": "postgres",
        })
        self.assertEqual(result["inventory"]["references"]["networks"], {"infra_default": ["postgres"]})

    def test_preserves_mount_type_and_read_only_identity(self):
        source = json.loads(FIXTURE.read_text())
        source["containers"][0]["Mounts"][0].update({"Type": "bind", "RW": False})
        mount = self.collector.collect_fixture(source)["inventory"]["containers"][0]["mounts"][0]
        self.assertEqual(mount["type"], "bind")
        self.assertTrue(mount["read_only"])

    def test_joins_container_image_to_inspected_repo_digest(self):
        source = json.loads(FIXTURE.read_text())
        image_id = "sha256:" + "a" * 64
        digest = "sha256:" + "d" * 64
        source["containers"][0].update({"Image": image_id, "ImageName": "postgres:17", "ImageDigest": ""})
        source["images"] = [{"id": image_id, "digests": ["docker.io/library/postgres@" + digest], "names": ["postgres:17"]}]
        container = self.collector.collect_fixture(source)["inventory"]["containers"][0]
        self.assertEqual(container["image_digest"], digest)
        self.assertEqual(container["image_provenance"], "immutable-digest")

    def test_rejects_secret_bearing_or_unknown_fixture_fields(self):
        source = json.loads(FIXTURE.read_text())
        source["containers"][0]["Environment"] = ["PASSWORD=hunter2"]
        with self.assertRaises(self.collector.InventoryHalt):
            self.collector.collect_fixture(source)
        source = json.loads(FIXTURE.read_text())
        source["secret"] = "value"
        with self.assertRaises(self.collector.InventoryHalt):
            self.collector.collect_fixture(source)

    def test_live_mode_uses_exact_read_only_command_allowlist(self):
        responses = {
            ("podman", "ps", "--all", "--quiet", "--no-trunc"): "",
            ("zfs", "list", "-H", "-o", "name,mountpoint"): "fast\t/fast\n",
        }

        def run(command, **kwargs):
            key = tuple(command)
            self.assertIn(key, responses)
            return subprocess.CompletedProcess(command, 0, responses[key], "")

        with mock.patch.object(self.collector.subprocess, "run", side_effect=run) as called:
            result = self.collector.collect_live()
        self.assertEqual(called.call_count, 2)
        self.assertEqual(result["inventory"]["containers"], [])

    def test_live_inspect_is_identity_checked_and_discards_environment(self):
        container_id = "b" * 64
        inspected = [{
            "Id": container_id, "Image": "sha256:" + "a" * 64, "Name": "/postgres",
            "Config": {"Image": "postgres:17", "Env": ["PASSWORD=sentinel"], "Labels": {
                "com.docker.compose.project": "infra",
            }},
            "State": {"Status": "exited"}, "Mounts": [],
            "NetworkSettings": {"Networks": {"infra_default": {}}},
        }]
        responses = {
            ("podman", "ps", "--all", "--quiet", "--no-trunc"): container_id + "\n",
            ("podman", "container", "inspect", container_id): json.dumps(inspected),
            ("zfs", "list", "-H", "-o", "name,mountpoint"): "fast\t/fast\n",
        }
        with mock.patch.object(
            self.collector.subprocess, "run",
            side_effect=lambda command, **kwargs: subprocess.CompletedProcess(command, 0, responses[tuple(command)], ""),
        ):
            result = self.collector.collect_live()
        rendered = json.dumps(result)
        self.assertNotIn("sentinel", rendered)
        self.assertEqual(result["inventory"]["containers"][0]["image_provenance"], "unresolved")

    def test_live_inspect_rejects_missing_duplicate_and_malformed_results(self):
        container_id = "b" * 64
        valid = {
            "Id": container_id, "Image": "sha256:" + "a" * 64, "Name": "/postgres",
            "Config": {"Image": "postgres:17", "Labels": {}},
            "State": {"Status": "exited"}, "Mounts": [], "NetworkSettings": {"Networks": {}},
        }
        cases = [[], [valid, valid], [{**valid, "Config": []}], [{**valid, "Id": "c" * 64}]]
        for response in cases:
            with self.subTest(response=response):
                outputs = iter([container_id + "\n", json.dumps(response)])
                with mock.patch.object(self.collector, "_run", side_effect=lambda command: next(outputs)):
                    with self.assertRaises(self.collector.InventoryHalt):
                        self.collector.collect_live()

    def test_command_policy_contains_no_remote_or_mutating_verbs(self):
        tokens = {token.lower() for command in self.collector.LIVE_COMMANDS for token in command}
        for forbidden in ("ssh", "rm", "prune", "destroy", "stop", "start", "restart", "exec"):
            self.assertNotIn(forbidden, tokens)

    def test_remote_sanitizer_drops_environment_before_transport(self):
        raw = [{
            "Id": "b" * 64, "Image": "sha256:" + "a" * 64, "Name": "/postgres",
            "Config": {"Image": "postgres:17", "Env": ["PASSWORD=sentinel"], "Labels": {
                "com.docker.compose.project": "infra",
            }},
            "State": {"Status": "exited"}, "Mounts": [{
                "Type": "bind", "Source": "/fast/apps/postgres", "Destination": "/data", "Name": "", "RW": False,
            }],
            "NetworkSettings": {"Networks": {"infra_default": {}}},
        }]
        with tempfile.TemporaryDirectory() as directory:
            inspect = pathlib.Path(directory) / "inspect.json"
            datasets = pathlib.Path(directory) / "datasets.tsv"
            images = pathlib.Path(directory) / "images.json"
            volumes = pathlib.Path(directory) / "volumes.json"
            networks = pathlib.Path(directory) / "networks.json"
            snapshots = pathlib.Path(directory) / "snapshots.txt"
            inspect.write_text(json.dumps(raw))
            datasets.write_text("fast\t/fast\n")
            images.write_text(json.dumps([{"Id": "sha256:" + "a" * 64, "RepoDigests": [], "RepoTags": ["postgres:17"]}]))
            volumes.write_text(json.dumps([{"Name": "redis_data", "Driver": "local", "Mountpoint": "/vol/redis", "Labels": {}}]))
            networks.write_text(json.dumps([{"id": "c" * 64, "name": "infra_default", "driver": "bridge", "labels": {}}]))
            snapshots.write_text("fast@pre-k1\n")
            completed = subprocess.run(
                ["bash", str(REMOTE), "--fixture", str(inspect), str(datasets), str(images), str(volumes), str(networks), str(snapshots)],
                check=True, capture_output=True, text=True,
            )
        self.assertNotIn("sentinel", completed.stdout)
        source = json.loads(completed.stdout)
        self.assertNotIn("Env", json.dumps(source))
        inventory = self.collector.collect_fixture(source)["inventory"]
        self.assertEqual(inventory["containers"][0]["mounts"][0]["type"], "bind")
        self.assertTrue(inventory["containers"][0]["mounts"][0]["read_only"])
        self.assertEqual(inventory["images"][0]["names"], ["postgres:17"])
        self.assertEqual(inventory["volumes"][0]["name"], "redis_data")
        self.assertEqual(inventory["networks"][0]["name"], "infra_default")
        self.assertEqual(inventory["snapshots"], [{"name": "fast@pre-k1"}])

    def test_remote_script_has_read_only_runtime_commands(self):
        script = REMOTE.read_text()
        self.assertIn("podman ps --all --quiet --no-trunc", script)
        self.assertIn('podman container inspect "${ids[@]}"', script)
        self.assertIn("zfs list -H -o name,mountpoint", script)
        self.assertIn("podman image list --quiet --no-trunc", script)
        self.assertIn("podman volume list --quiet", script)
        self.assertIn("podman network list --quiet --no-trunc", script)
        self.assertIn("zfs list -H -t snapshot -o name", script)
        self.assertNotIn("--argjson", script)
        self.assertNotIn("--arg datasets", script)
        for forbidden in ("podman rm", "podman stop", "podman start", "prune", "zfs destroy", "ssh "):
            self.assertNotIn(forbidden, script)

    def test_remote_sanitizer_streams_large_metadata_without_argv_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [pathlib.Path(directory) / name for name in (
                "containers.json", "datasets.tsv", "images.json", "volumes.json",
                "networks.json", "snapshots.txt",
            )]
            paths[0].write_text("[]")
            paths[1].write_text("fast\t/fast\n")
            large_names = ["repo/image:" + str(index) + "x" * 120 for index in range(12000)]
            paths[2].write_text(json.dumps([{"Id": "sha256:" + "a" * 64, "RepoDigests": [], "RepoTags": large_names}]))
            paths[3].write_text("[]")
            paths[4].write_text("[]")
            paths[5].write_text("fast@pre-k1\n")
            completed = subprocess.run(
                ["bash", str(REMOTE), "--fixture", *(str(path) for path in paths)],
                check=True, capture_output=True, text=True,
            )
        source = json.loads(completed.stdout)
        self.assertEqual(len(source["images"][0]["names"]), 12000)


if __name__ == "__main__":
    unittest.main()
