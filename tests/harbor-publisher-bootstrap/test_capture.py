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
import fcntl, json, os, pathlib, runpy, ssl, subprocess, sys, urllib.error, urllib.request
from types import SimpleNamespace

mode = os.environ["CAPTURE_TEST_CASE"]
if mode == "environment-proxy":
    for key in ("http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
        os.environ[key] = "http://synthetic-proxy.invalid:8123"
    os.environ["no_proxy"] = os.environ["NO_PROXY"] = ""
store = pathlib.Path("secrets/sops/secrets.yaml").resolve()
lock = store.with_name(".secrets.yaml.harbor-publisher.lock")
events = []
root = "fixture-root-token"
role = "fixture-controller-role-id"
replacement = 'fixture-new-"\\-secret-id'
field = '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]'
held_lock = None
if mode == "lock-held":
    held_lock = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(held_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

native_replace = os.replace
def replace(source, target):
    if mode == "late-cooperating-writer":
        with lock.open("a+b") as writer:
            try:
                fcntl.flock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                events.append({"kind": "writer", "blocked": True})
            else:
                data = json.loads(store.read_text())
                data["operator_edit"] = "must-not-be-lost"
                store.write_text(json.dumps(data))
                events.append({"kind": "writer", "blocked": False})
            events.append({"kind": "lock-inode", "inode": lock.stat().st_ino})
    return native_replace(source, target)
os.replace = replace

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
        json_output = args[4:6] == ["--output-type", "json"]
        source = args[6] if json_output else args[4]
        if key == '["vault_root_token"]':
            value = root + ("\n" if mode == "whitespace" else "")
        elif key == '["homelab_iac"]["openbao_harbor_fleet_readers_publisher_role_id"]':
            value = role
        else:
            assert key == field
            data = json.loads(pathlib.Path(source).read_text())["homelab_iac"]
            if "openbao_harbor_fleet_readers_publisher_secret_id" not in data:
                return SimpleNamespace(returncode=1, stdout=b"", stderr=b"missing field")
            value = data["openbao_harbor_fleet_readers_publisher_secret_id"]
        return SimpleNamespace(returncode=0, stdout=(json.dumps(value) if json_output else value).encode(), stderr=b"")
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
    def open(self, request, timeout):
        context = next(handler._context for handler in self.handlers
                       if isinstance(handler, urllib.request.HTTPSHandler))
        assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
        assert context.keylog_filename is None
        if mode == "environment-proxy":
            events.append({"kind": "proxy-routing", "inherited": any(
                isinstance(handler, urllib.request.ProxyHandler) and bool(handler.proxies)
                for handler in self.handlers)})
        assert request.full_url.startswith("https://openbao.homelab.pastelariadev.com/v1/auth/approle/role/svc-homelab-iac-openbao-harbor-fleet-readers-publisher/")
        assert request.headers["X-vault-token"] == root
        assert "X-vault-namespace" not in request.headers
        assert timeout > 0
        path = request.full_url.split(".com", 1)[1]
        events.append({"kind": "api", "method": request.get_method(), "path": path})
        if mode == "redirect":
            redirect = next(handler for handler in self.handlers
                            if isinstance(handler, urllib.request.HTTPRedirectHandler))
            redirect.redirect_request(request, None, 302, "", {}, "https://untrusted.invalid/")
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

subprocess.run = sops
# Keep actual stdlib opener construction; intercept only its network operation.
urllib.request.OpenerDirector.open = Opener.open
try:
    script = sys.argv[1]
    sys.argv = sys.argv[1:]
    runpy.run_path(script, run_name="__main__")
finally:
    if held_lock is not None:
        os.close(held_lock)
    if lock.exists():
        with lock.open("a+b") as released:
            fcntl.flock(released, fcntl.LOCK_EX | fcntl.LOCK_NB)
        events.append({"kind": "released-lock", "mode": lock.stat().st_mode & 0o777,
                       "inode": lock.stat().st_ino})
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
            if case == "missing-target":
                del original["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"]
            elif case.startswith("invalid-target-"):
                original["homelab_iac"]["openbao_harbor_fleet_readers_publisher_secret_id"] = {
                    "mapping": {"unexpected": "value"}, "list": ["value"], "null": None,
                    "number": 7, "boolean": True, "empty": "", "whitespace": " value ",
                }[case.removeprefix("invalid-target-")]
            store.write_text(json.dumps(original))
            harness = sandbox / "harness.py"
            harness.write_text(HARNESS)
            binary = sandbox / "bin/python3"
            binary.parent.mkdir()
            binary.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{harness}" "$@"\n')
            binary.chmod(0o755)
            env = os.environ.copy()
            env.update(PATH=str(binary.parent) + os.pathsep + os.environ["PATH"], CAPTURE_TEST_CASE=case)
            command = ["just", "--no-dotenv", RECIPE]
            if case != "missing-acknowledgement":
                command.append("--dry-run" if case == "unexpected-args" else "--exclusive-secret-store")
            result = subprocess.run(command, cwd=sandbox, env=env,
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

    def test_missing_or_non_string_target_fails_before_issuance(self):
        for case in ("missing-target", *("invalid-target-" + kind for kind in (
            "mapping", "list", "null", "number", "boolean", "empty", "whitespace",
        ))):
            with self.subTest(case=case):
                result, events, original, after, _ = self.run_capture(case)
                self.assertFalse(any(e.get("method") == "POST" for e in events),
                                 "Invalid existing target must fail before irreversible SecretID POST")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(after, original)

    def test_unknown_arguments_are_rejected_before_any_secret_read_or_issuance(self):
        result, events, original, after, _ = self.run_capture("unexpected-args")
        self.assertEqual(result.returncode, 64, "Unknown arguments must not silently issue a credential")
        self.assertEqual(events, [])
        self.assertEqual(after, original)

    def test_single_writer_acknowledgement_required_before_secret_reads_or_issuance(self):
        result, events, original, after, _ = self.run_capture("missing-acknowledgement")
        self.assertEqual(result.returncode, 64, "Unacknowledged single-writer window must not issue a credential")
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

    def test_conflicting_store_lock_fails_before_secret_reads_or_issuance(self):
        result, events, original, after, _ = self.run_capture("lock-held")
        self.assertNotEqual(result.returncode, 0, "Conflicting writer lock must stop capture before POST")
        self.assertFalse(any(e["kind"] in ("api", "sops") for e in events))
        self.assertEqual(after, original)

    def test_actual_opener_disables_inherited_https_proxy(self):
        result, events, _, _, _ = self.run_capture("environment-proxy")
        routing = [e for e in events if e["kind"] == "proxy-routing"]
        self.assertTrue(routing, "Must exercise actual stdlib opener construction")
        self.assertFalse(any(e["inherited"] for e in routing),
                         "Actual opener must not inherit synthetic HTTPS_PROXY")
        self.assertEqual(result.returncode, 0)

    def test_cooperating_writer_is_blocked_between_comparison_and_replace(self):
        result, events, _, after, _ = self.run_capture("late-cooperating-writer")
        self.assertEqual([e for e in events if e["kind"] == "writer"],
                         [{"kind": "writer", "blocked": True}],
                         "Late cooperating writer must not enter comparison/replace window")
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("operator_edit", after)
        self.assertEqual(len([e for e in events if e.get("method") == "POST"]), 1)
        released = next(e for e in events if e["kind"] == "released-lock")
        self.assertEqual(released["mode"], 0o600)
        self.assertEqual(released["inode"], next(e["inode"] for e in events if e["kind"] == "lock-inode"),
                         "Stable lock inode must not be unlinked on release")


if __name__ == "__main__":
    unittest.main()
