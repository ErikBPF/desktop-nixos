import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[2]
RECIPE = "capture-harbor-fleet-publisher-secret-id"
SCRIPT = "scripts/capture-harbor-fleet-publisher-secret-id.py"
ROLE = "svc-homelab-iac-openbao-harbor-fleet-readers-publisher"
PREFIX = "/v1/auth/approle/role/" + ROLE
FIELD = '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]'

# This child intercepts every Sops command and HTTP request before running the
# real owner helper through Just. No real secret store or network is consulted.
HARNESS = r'''
import json, os, pathlib, runpy, ssl, subprocess, sys, urllib.error, urllib.request
from types import SimpleNamespace

mode = os.environ["CAPTURE_TEST_CASE"]
store = pathlib.Path("secrets/sops/secrets.yaml").resolve()
events = []
root = "fixture-root-token"
role = "fixture-controller-role-id"
replacement = 'fixture-new-"\\-secret-id'
field = '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]'

def sops(args, **kwargs):
    assert args[0] == "sops", "Only Sops may be executed by helper"
    assert all(value not in " ".join(args) for value in (root, role, replacement))
    assert kwargs.get("capture_output") is True
    assert kwargs.get("timeout") is not None
    assert not any(value in str(kwargs.get("env", {})) for value in (root, role, replacement))
    events.append({"kind": "sops", "args": args[1:]})
    if args[1:] == ["set", "--help"]:
        return SimpleNamespace(returncode=0, stdout=b"unsupported" if mode == "unsupported" else b"--value-stdin", stderr=b"")
    if args[1:3] == ["--decrypt", "--extract"]:
        key = args[3]
        if key == '["vault_root_token"]':
            value = root + ("\n" if mode == "whitespace" else "")
        elif key == '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_role_id"]':
            value = role
        else:
            assert key == field
            value = json.loads(pathlib.Path(args[4]).read_text())["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]
        return SimpleNamespace(returncode=0, stdout=value.encode(), stderr=b"")
    assert args[:3] == ["sops", "set", "--value-stdin"]
    assert args[4] == field and len(args) == 5
    assert json.loads(kwargs["input"]) == replacement
    staged = pathlib.Path(args[3])
    assert staged != store and staged.parent == store.parent
    assert staged.stat().st_mode & 0o777 == 0o600
    if mode == "persist-failure":
        return SimpleNamespace(returncode=1, stdout=replacement.encode(), stderr=root.encode())
    data = json.loads(staged.read_text())
    data["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"] = replacement
    staged.write_text(json.dumps(data))
    if mode == "concurrent-change":
        original = json.loads(store.read_text())
        original["operator_edit"] = "preserve-concurrent-work"
        store.write_text(json.dumps(original))
    return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

class Response:
    def __init__(self, data): self.data = data
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return b"" if self.data is None else json.dumps(self.data).encode()

class Opener:
    def __init__(self, handlers): self.handlers = handlers
    def open(self, request, timeout):
        assert request.full_url.startswith("https://openbao.homelab.pastelariadev.com/v1/auth/approle/role/svc-homelab-iac-openbao-harbor-fleet-readers-publisher/")
        assert request.headers["X-vault-token"] == root
        assert "X-vault-namespace" not in request.headers
        assert timeout > 0
        path = request.full_url.split(".com", 1)[1]
        events.append({"kind": "api", "method": request.get_method(), "path": path})
        if mode == "redirect":
            self.handlers[1].redirect_request(request, None, 302, "", {}, "https://untrusted.invalid/")
            raise AssertionError("Redirect must be refused")
        if request.get_method() == "GET":
            assert path.endswith("/role-id") and request.data is None
            if mode == "lookup-forbidden":
                raise urllib.error.HTTPError(request.full_url, 403, root, {}, None)
            if mode == "lookup-empty":
                return Response(None)
            return Response({"data": {"role_id": "wrong-controller" if mode == "mismatch" else role}})
        assert request.get_method() == "POST" and path.endswith("/secret-id")
        assert json.loads(request.data) == {}
        if mode == "issue-failure":
            raise urllib.error.HTTPError(request.full_url, 500, replacement, {}, None)
        if mode == "issue-empty":
            return Response(None)
        return Response({"data": {"secret_id": None if mode == "invalid-response" else replacement}})

def opener(*handlers):
    context = handlers[0]._context
    assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
    assert context.keylog_filename is None
    return Opener(handlers)

subprocess.run = sops
urllib.request.build_opener = opener
try:
    script = sys.argv[1]
    sys.argv = [script] + (["--dry-run"] if mode == "unexpected-args" else [])
    runpy.run_path(script, run_name="__main__")
finally:
    pathlib.Path("events.json").write_text(json.dumps(events))
'''


class CaptureTests(unittest.TestCase):
    def run_capture(self, case="success"):
        with tempfile.TemporaryDirectory() as temporary:
            sandbox = Path(temporary)
            shutil.copyfile(ROOT / "justfile", sandbox / "justfile")
            shutil.copyfile(ROOT / "fleet.json", sandbox / "fleet.json")
            script = ROOT / SCRIPT
            if script.exists():
                (sandbox / "scripts").mkdir()
                shutil.copyfile(script, sandbox / SCRIPT)
            store = sandbox / "secrets/sops/secrets.yaml"
            store.parent.mkdir(parents=True)
            original = {
                "homelab_iac": {
                    "openbao_harbor_fleet_readers_publisher_role_id": "fixture-controller-role-id",
                    "openbao_harbor_fleet_readers_publisher_secret_id": "fixture-existing-id",
                    "other_bootstrap": "preserved",
                },
                "reader_credentials": ["unchanged-discovery", "unchanged-endeavour", "unchanged-kepler"],
                "cognee_credential": "unchanged-cognee",
                "sops": {"recipient": "preserved-recipient"},
            }
            store.write_text(json.dumps(original))
            harness = sandbox / "harness.py"
            harness.write_text(HARNESS)
            binary = sandbox / "bin/python3"
            binary.parent.mkdir()
            binary.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{harness}" "$@"\n')
            binary.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=str(binary.parent) + os.pathsep + os.environ["PATH"], CAPTURE_TEST_CASE=case)
            result = subprocess.run(["just", "--no-dotenv", RECIPE], cwd=sandbox, env=env,
                                    capture_output=True, text=True, timeout=20, check=False)
            events_file = sandbox / "events.json"
            events = json.loads(events_file.read_text()) if events_file.exists() else []
            after = json.loads(store.read_text())
            self.assertFalse(list(store.parent.glob(".harbor-fleet-publisher-*")), "Encrypted transaction copies must be cleaned up")
            for value in ("fixture-root-token", "fixture-controller-role-id", 'fixture-new-"\\-secret-id'):
                self.assertNotIn(value, result.stdout + result.stderr, "Credential leaked into command output")
            return result, events, original, after, store.stat().st_mode & 0o777

    def test_positive_pipeline_issues_once_and_changes_only_controller_secret_id(self):
        result, events, original, after, mode = self.run_capture()
        self.assertEqual(result.returncode, 0, "Controller-only capture must complete without bulk reader rotation")
        self.assertEqual([e for e in events if e["kind"] == "api"], [
            {"kind": "api", "method": "GET", "path": PREFIX + "/role-id"},
            {"kind": "api", "method": "POST", "path": PREFIX + "/secret-id"},
        ])
        sets = [e for e in events if e["kind"] == "sops" and e["args"][:2] == ["set", "--value-stdin"]]
        self.assertEqual(len(sets), 1)
        self.assertEqual(sets[0]["args"][-1], FIELD)
        after["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"] = original["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]
        self.assertEqual(after, original, "All other logical fields must remain byte-for-byte equal")
        self.assertEqual(mode, 0o600)

    def test_wrong_role_or_forbidden_lookup_never_issues(self):
        for case in ("mismatch", "lookup-forbidden", "lookup-empty", "redirect"):
            with self.subTest(case=case):
                result, events, original, after, _ = self.run_capture(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len([e for e in events if e["kind"] == "api"]), 1)
                self.assertFalse(any(e.get("method") == "POST" for e in events))
                self.assertEqual(after, original)

    def test_unsupported_sops_or_whitespace_never_reaches_api(self):
        for case in ("unsupported", "whitespace"):
            with self.subTest(case=case):
                result, events, original, after, _ = self.run_capture(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(e["kind"] == "api" for e in events))
                self.assertEqual(after, original)

    def test_unknown_arguments_are_rejected_before_any_secret_read_or_issuance(self):
        result, events, original, after, _ = self.run_capture("unexpected-args")
        self.assertEqual(result.returncode, 64, "Unknown arguments must not silently issue a credential")
        self.assertEqual(events, [])
        self.assertEqual(after, original)

    def test_issue_or_capture_failure_stops_without_retry_or_existing_id_revocation(self):
        for case in ("issue-failure", "issue-empty", "invalid-response", "persist-failure"):
            with self.subTest(case=case):
                result, events, original, after, _ = self.run_capture(case)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len([e for e in events if e.get("method") == "POST"]), 1)
                self.assertEqual(after, original)
                self.assertIn("do not rerun", result.stderr)

    def test_concurrent_sops_edit_is_preserved_and_no_second_id_issued(self):
        result, events, original, after, _ = self.run_capture("concurrent-change")
        self.assertNotEqual(result.returncode, 0)
        original["operator_edit"] = "preserve-concurrent-work"
        self.assertEqual(after, original)
        self.assertEqual(len([e for e in events if e.get("method") == "POST"]), 1)


if __name__ == "__main__":
    unittest.main()
