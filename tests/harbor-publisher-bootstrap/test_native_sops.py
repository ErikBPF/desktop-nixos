"""Native Sops regression: disposable age identity, fake store, intercepted HTTP."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml
from test_capture import FIELD, PREFIX, ROOT, SCRIPT

HARNESS = r'''
import json, pathlib, runpy, subprocess, sys, urllib.request

events = {"get": 0, "post": 0, "target_extract": 0, "set": 0}
native_run = subprocess.run
field = '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]'
def sops(args, **kwargs):
    assert args[0] == "sops"
    if args[1:3] == ["--decrypt", "--extract"]:
        assert args[3] in (field, '["vault_root_token"]',
                          '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_role_id"]')
        events["target_extract"] += args[3] == field
    else:
        assert args[1:3] in (["set", "--help"], ["set", "--value-stdin"])
        if args[2] == "--value-stdin":
            assert args[4] == field and json.loads(kwargs["input"]) == "fixture-new-id"
            events["set"] += 1
    return native_run(args, **kwargs)
subprocess.run = sops

class Response:
    def __init__(self, data): self.data = data
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return json.dumps({"data": self.data}).encode()

def open_fake(self, request, timeout):
    prefix = "https://openbao.homelab.pastelariadev.com" + sys.fixture_prefix
    assert request.headers["X-vault-token"] == "fixture-root"
    if request.get_method() == "GET":
        assert request.full_url == prefix + "/role-id" and request.data is None
        events["get"] += 1
        return Response({"role_id": "fixture-role"})
    assert request.get_method() == "POST" and request.full_url == prefix + "/secret-id"
    assert json.loads(request.data) == {}
    events["post"] += 1
    return Response({"secret_id": "fixture-new-id"})

urllib.request.OpenerDirector.open = open_fake
sys.fixture_prefix = sys.argv.pop()
sys.argv = sys.argv[1:]
try:
    runpy.run_path(sys.argv[0], run_name="__main__")
finally:
    pathlib.Path("events.json").write_text(json.dumps(events))
'''


class NativeSopsTests(unittest.TestCase):
    def test_native_scalar_type_and_single_field_roundtrip(self):
        # Missing tools are a failed gate, never a skipped native regression.
        for binary in ("sops", "age-keygen"):
            self.assertIsNotNone(shutil.which(binary), f"Native gate requires {binary}")
        with tempfile.TemporaryDirectory(prefix="harbor-native-sops-") as temporary:
            sandbox = Path(temporary)
            env = {key: value for key, value in os.environ.items() if not key.startswith("SOPS_")}
            env.update(HOME=temporary, XDG_CONFIG_HOME=temporary,
                       SOPS_AGE_KEY_FILE=str(sandbox / "age-key.txt"))

            def native(*args, payload=None):
                result = subprocess.run(args, input=payload, env=env, cwd=sandbox,
                                        capture_output=True, timeout=30, check=False)
                self.assertEqual(result.returncode, 0, "Disposable native Sops fixture command failed")
                return result.stdout

            native("age-keygen", "-o", env["SOPS_AGE_KEY_FILE"])
            recipient = native("age-keygen", "-y", env["SOPS_AGE_KEY_FILE"]).decode().strip()
            config = sandbox / "sops-config.yaml"
            config.write_text("creation_rules:\n  - path_regex: .*\n")
            script = sandbox / SCRIPT
            script.parent.mkdir()
            shutil.copyfile(ROOT / SCRIPT, script)
            harness = sandbox / "harness.py"
            harness.write_text(HARNESS)
            store = sandbox / "secrets/sops/secrets.yaml"
            store.parent.mkdir(parents=True)
            for kind, target in (
                ("string", "fixture-existing-id"), ("number", 7), ("boolean", True),
                ("mapping", {"unexpected": "fixture-value"}), ("list", ["fixture-value"]),
                ("null", None), ("empty", ""), ("whitespace", " fixture-value "),
                ("newline", "fixture-value\n"), ("missing", None),
                ("changed-type-marker", 7),
            ):
                with self.subTest(kind=kind):
                    original = {"vault_root_token": "fixture-root", "homelab_iac": {
                        "openbao_harbor_fleet_readers_publisher_role_id": "fixture-role",
                        "openbao_harbor_fleet_readers_publisher_secret_id": target,
                        "other_bootstrap": "fixture-other",
                    }, "reader_credentials": ["fixture-reader"], "cognee_credential": "fixture-cognee"}
                    if kind == "missing":
                        del original["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]
                    store.write_bytes(native("sops", "--encrypt", "--config", str(config),
                                             "--age", recipient, "--input-type", "json",
                                             "--output-type", "yaml", "/dev/stdin",
                                             payload=json.dumps(original).encode()))
                    if kind == "changed-type-marker":
                        # Limitation, not tamper resistance: only the declared type changes.
                        encrypted = store.read_bytes()
                        scalar = yaml.safe_load(encrypted)["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]
                        self.assertTrue(scalar.endswith(",type:int]"))
                        self.assertEqual(encrypted.count(scalar.encode()), 1)
                        changed = scalar.removesuffix(",type:int]") + ",type:str]"
                        store.write_bytes(encrypted.replace(scalar.encode(), changed.encode(), 1))
                        interpreted = json.loads(native("sops", "--decrypt", "--output-type", "json", str(store)))
                        self.assertEqual(interpreted["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"],
                                         "7", "Sops MAC does not authenticate the changed scalar type")
                    before = store.read_bytes()
                    if kind == "string":
                        self.assertEqual(native("sops", "--decrypt", "--extract", FIELD,
                                                "--output-type", "json", str(store)),
                                         b"fixture-existing-id", "Native scalar must be raw, not JSON-quoted")
                    result = subprocess.run([sys.executable, str(harness), str(script),
                                             "--exclusive-secret-store", PREFIX],
                                            cwd=sandbox, env=env, capture_output=True, timeout=40, check=False)
                    events = json.loads((sandbox / "events.json").read_text())
                    self.assertFalse(list(store.parent.glob(".harbor-fleet-publisher-*")))
                    self.assertNotIn(b"fixture-", result.stdout + result.stderr)
                    self.assertNotIn(b"AGE-SECRET-KEY-", result.stdout + result.stderr)
                    if kind in ("string", "changed-type-marker"):
                        self.assertEqual(result.returncode, 0,
                                         "Native owner-declared string target must pass; changed markers are not authenticated; "
                                         f"generic operation counts: {events}")
                        self.assertEqual(events, {"get": 1, "post": 1, "target_extract": 2, "set": 1})
                        self.assertEqual(store.stat().st_mode & 0o777, 0o600)
                        after = json.loads(native("sops", "--decrypt", "--output-type", "json", str(store)))
                        self.assertEqual(after["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"],
                                         "fixture-new-id")
                        after["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"] = target
                        self.assertEqual(after, original, "Native set must preserve every other logical fixture field")
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(events["get"], 0, "Invalid target must stop before any HTTP request")
                        self.assertEqual(events["post"], 0, "Invalid target must stop before fake POST")
                        self.assertEqual(events["set"], 0)
                        self.assertEqual(store.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
