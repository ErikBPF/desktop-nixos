"""Behavioral controller contract; no cluster, credentials or ZFS required."""
import importlib.util
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "capture", Path(__file__).parents[2] / "modules/hosts/kepler/_wazuh-manager-capture.py"
)
controller = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(controller)


class API:
    def __init__(self, events):
        self.events = events
        self.fail_stop = False
        self.fail_recovery = False

    def preflight(self):
        self.events.append("preflight")
        return {"master": "uid-master", "worker": "uid-worker"}

    def scale(self, replicas):
        self.events.append(f"scale:{replicas}")
        if replicas == 0 and self.fail_stop:
            raise RuntimeError("stop failed")
        if replicas == 1 and self.fail_recovery:
            raise RuntimeError("restore failed")

    def wait_stopped(self):
        self.events.append("stopped")

    def wait_ready(self):
        self.events.append("ready")


class Storage:
    def __init__(self, events):
        self.events = events
        self.intent = None
        self.fail_snapshot = False

    def prepare(self):
        self.events.append("capacity")

    def save_intent(self, identities):
        self.intent = identities
        self.events.append("intent")

    def read_intent(self):
        return self.intent

    def verify_shutdown(self, identities):
        self.events.append("shutdown-proof")

    def snapshot(self):
        self.events.append("snapshot")
        if self.fail_snapshot:
            raise RuntimeError("snapshot failed")

    def export(self, identities):
        self.events.append("export")

    def clear_intent(self):
        self.events.append("clear")
        self.intent = None

    def cleanup(self):
        self.events.append("cleanup")


def test_capture_restores_before_export_and_persists_before_stop():
    events = []
    controller.capture(API(events), Storage(events))
    assert events == ["preflight", "capacity", "intent", "scale:0", "stopped",
                      "shutdown-proof", "snapshot", "scale:1", "ready", "clear", "export"]


@pytest.mark.parametrize("failure", ["stop", "snapshot"])
def test_failure_always_restores_without_export(failure):
    events = []
    api, storage = API(events), Storage(events)
    api.fail_stop = failure == "stop"
    storage.fail_snapshot = failure == "snapshot"
    with pytest.raises(RuntimeError):
        controller.capture(api, storage)
    assert "scale:1" in events and "export" not in events
    assert storage.intent is None


def test_failed_recovery_keeps_durable_intent():
    events = []
    api, storage = API(events), Storage(events)
    api.fail_recovery = True
    with pytest.raises(RuntimeError):
        controller.capture(api, storage)
    assert storage.intent is not None
    assert "clear" not in events and "export" not in events


def test_rescuer_recovers_existing_intent_without_capture():
    events = []
    storage = Storage(events)
    storage.intent = {"master": "uid-master", "worker": "uid-worker"}
    controller.recover(API(events), storage)
    assert events == ["scale:1", "ready", "clear"]


def test_rescuer_without_intent_makes_no_cluster_changes():
    events = []
    controller.recover(API(events), Storage(events))
    assert events == []


def ready_pod(uid, deletion_timestamp=None):
    metadata = {"uid": uid}
    if deletion_timestamp is not None:
        metadata["deletionTimestamp"] = deletion_timestamp
    return {"metadata": metadata,
            "status": {"conditions": [{"type": "Ready", "status": "True"}]}}


def test_recovery_waits_for_a_replacement_after_a_terminating_ready_pod(monkeypatch):
    import time
    clock = [0.0]
    monkeypatch.setattr(time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(time, "sleep", lambda seconds: clock.__setitem__(0, clock[0] + seconds))
    cluster = object.__new__(controller.Cluster)
    served = {"master": 0, "worker": 0}

    def request(path, replicas=None):
        for role in controller.MANAGERS:
            if path == cluster.scale_path(role):
                return {}
            if path == cluster.pod_path(role):
                served[role] += 1
                if served[role] == 1:
                    return ready_pod("old-" + role, "2026-01-01T00:00:00Z")
                return ready_pod("new-" + role)
        raise AssertionError("unexpected API request " + path)

    cluster.request = request
    storage = Storage([])
    storage.intent = {"master": "uid-master", "worker": "uid-worker"}
    cleared = []

    def clear_intent():
        cleared.append(dict(served))
        storage.intent = None

    storage.clear_intent = clear_intent
    controller.recover(cluster, storage)
    assert cleared == [{"master": 2, "worker": 2}], "intent cleared before a healthy replacement"
    assert clock[0] > 0, "wait did not continue past the terminating Ready pod"
    assert storage.intent is None


def delegation():
    return {"spec": {"syncPolicy": {"syncOptions": ["RespectIgnoreDifferences=true"]},
                     "ignoreDifferences": [
                         {"group": "apps", "kind": "StatefulSet", "namespace": "wazuh",
                          "name": f"wazuh-manager-{role}", "jsonPointers": ["/spec/replicas"]}
                         for role in ("master", "worker")]}}


def test_delegation_requires_current_application_policy():
    controller.check_delegation(delegation())
    for application in ({}, {"spec": {"ignoreDifferences": delegation()["spec"]["ignoreDifferences"]}}):
        with pytest.raises(ValueError):
            controller.check_delegation(application)


def test_delegation_requires_each_exact_manager():
    app = delegation()
    app["spec"]["ignoreDifferences"][0]["name"] = "*"
    with pytest.raises(ValueError):
        controller.check_delegation(app)


def binding(role):
    uid = controller.BINDINGS[role]
    pvc = f"wazuh-manager-{role}-wazuh-manager-{role}-0"
    return ({"metadata": {"uid": uid, "name": pvc},
             "spec": {"volumeName": "pvc-" + uid}, "status": {"phase": "Bound"}},
            {"metadata": {"name": "pvc-" + uid}, "status": {"phase": "Bound"},
             "spec": {"claimRef": {"uid": uid, "name": pvc, "namespace": "wazuh"},
                      "csi": {"driver": "nfs.csi.k8s.io", "volumeHandle": f"10.250.0.1#fast/k8s#pvc-{uid}##", "volumeAttributes": {"server": "10.250.0.1", "share": "/fast/k8s", "subdir": "pvc-" + uid}}}})


@pytest.mark.parametrize("changed", ["uid", "server", "share", "phase", "volume_phase"])
def test_binding_change_fails_closed(changed):
    claim, volume = binding("master")
    controller.check_binding("master", claim, volume)
    if changed == "uid":
        volume["spec"]["claimRef"]["uid"] = "replacement"
    elif changed == "phase":
        claim["status"]["phase"] = "Lost"
    elif changed == "volume_phase":
        volume["status"]["phase"] = "Released"
    else:
        volume["spec"]["csi"]["volumeAttributes"][changed] = "unexpected"
    with pytest.raises(ValueError):
        controller.check_binding("master", claim, volume)


def test_recovery_attempts_both_managers_even_if_first_api_fails():
    cluster = object.__new__(controller.Cluster)
    calls = []
    def request(path, replicas):
        calls.append((path, replicas))
        if "master" in path:
            raise RuntimeError("API unavailable")
    cluster.request = request
    with pytest.raises(RuntimeError):
        cluster.scale(1)
    assert len(calls) == 2 and all(replicas == 1 for _, replicas in calls)


def test_request_deadline_aborts_a_trickling_response(monkeypatch, tmp_path):
    import http.server
    import threading
    import time

    stop = threading.Event()

    class Trickle(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "10000")
            self.end_headers()
            self.wfile.write(b"{")
            self.wfile.flush()
            while not stop.wait(0.1):
                try:
                    self.wfile.write(b" ")
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    return

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Trickle)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        cluster = object.__new__(controller.Cluster)
        cluster.endpoint = f"http://127.0.0.1:{server.server_address[1]}"
        cluster.context = None
        cluster.token_file = tmp_path / "token"
        cluster.token_file.write_text("token")
        monkeypatch.setattr(controller, "API_REQUEST_TIMEOUT_SECONDS", 0.5)
        started = time.monotonic()
        with pytest.raises(TimeoutError, match="deadline"):
            cluster.request("/api/v1/namespaces/wazuh/pods/wazuh-manager-master-0")
        assert time.monotonic() - started < 3, "trickling body outlived the deadline"
    finally:
        stop.set()
        server.shutdown()
        server.server_close()


def local_cluster(server, tmp_path):
    cluster = object.__new__(controller.Cluster)
    cluster.endpoint = f"http://127.0.0.1:{server.server_address[1]}"
    cluster.context = None
    cluster.token_file = tmp_path / "token"
    cluster.token_file.write_text("token")
    return cluster


def test_request_deadline_bounds_a_trickling_header(monkeypatch, tmp_path):
    import http.server
    import threading
    import time

    stop = threading.Event()
    calls = []
    slow = controller.Cluster.pod_path("master")

    class TrickleHeader(http.server.BaseHTTPRequestHandler):
        def respond(self):
            length = int(self.headers.get("Content-Length", 0))
            if length:
                self.rfile.read(length)
            calls.append(f"{self.command} {self.path}")
            if self.path == slow:
                # A complete status line, then header bytes one at a time with no
                # terminating blank line: urllib's socket timeout never fires.
                self.wfile.write(b"HTTP/1.1 200 OK\r\n")
                self.wfile.flush()
                while not stop.is_set():
                    for byte in b"X-Slow: a\r\n":
                        if stop.wait(0.02):
                            return
                        try:
                            self.wfile.write(bytes((byte,)))
                            self.wfile.flush()
                        except OSError:
                            return
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", "2")
            self.end_headers()
            self.wfile.write(b"{}")

        do_GET = do_PATCH = respond

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), TrickleHeader)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        cluster = local_cluster(server, tmp_path)
        monkeypatch.setattr(controller, "API_REQUEST_TIMEOUT_SECONDS", 0.5)
        started = time.monotonic()
        with pytest.raises(TimeoutError, match="deadline"):
            cluster.request(slow)
        elapsed = time.monotonic() - started
        assert 0.4 <= elapsed < 3, f"trickling header outlived the deadline ({elapsed:.2f} s)"
        cluster.scale(1)
        assert calls[-2:] == [f"PATCH {controller.Cluster.scale_path(role)}"
                              for role in controller.MANAGERS]
    finally:
        stop.set()
        server.shutdown()
        server.server_close()


def test_request_deadline_bounds_a_trickling_tls_handshake(monkeypatch, tmp_path):
    import socket
    import ssl
    import threading
    import time

    stop = threading.Event()
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()

    def serve():
        conn, _ = listener.accept()
        with conn:
            try:
                conn.recv(4096)
                # A valid 16 KiB TLS handshake record, then one body byte at a
                # time. The handshake must be cut at the request deadline.
                conn.sendall(b"\x16\x03\x03\x40\x00")
                while not stop.wait(0.02):
                    conn.sendall(b" ")
            except OSError:
                pass

    threading.Thread(target=serve, daemon=True).start()
    real_connect = socket.create_connection

    def delayed_connect(address, timeout=None):
        # Spend 0.4 s of the 0.5 s budget before the handshake. A fresh
        # handshake timeout would then end near 0.9 s, not at the deadline.
        sock = real_connect(address, timeout=timeout)
        time.sleep(0.4)
        return sock

    monkeypatch.setattr(socket, "create_connection", delayed_connect)
    try:
        cluster = object.__new__(controller.Cluster)
        cluster.endpoint = f"https://127.0.0.1:{listener.getsockname()[1]}"
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        cluster.context = context
        cluster.token_file = tmp_path / "token"
        cluster.token_file.write_text("token")
        monkeypatch.setattr(controller, "API_REQUEST_TIMEOUT_SECONDS", 0.5)
        started = time.monotonic()
        with pytest.raises(TimeoutError, match="deadline"):
            cluster.request(controller.Cluster.pod_path("master"))
        elapsed = time.monotonic() - started
        assert 0.4 <= elapsed < 0.8, f"handshake did not share the deadline ({elapsed:.2f} s)"
    finally:
        stop.set()
        listener.close()


def test_request_returns_parsed_json_within_the_deadline(tmp_path):
    import http.server
    import threading

    class Normal(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = b'{"spec": {"replicas": 1}}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Normal)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        cluster = local_cluster(server, tmp_path)
        assert cluster.request(controller.Cluster.scale_path("master")) == {"spec": {"replicas": 1}}
    finally:
        server.shutdown()
        server.server_close()


def test_atomic_state_is_private_and_replaces_complete_json(tmp_path):
    import json
    import stat
    path = tmp_path / "intent.json"
    controller.atomic_json(path, {"generation": 1})
    controller.atomic_json(path, {"generation": 2})
    assert json.loads(path.read_text()) == {"generation": 2}
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert list(tmp_path.iterdir()) == [path]


def test_cleanup_rejects_unowned_snapshot_before_any_command(tmp_path, monkeypatch):
    import json
    import subprocess
    storage = controller.LocalStorage(tmp_path, tmp_path)
    (tmp_path / "snapshot.json").write_text(json.dumps({"name": "fast-pool/data@unrelated"}))
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: pytest.fail("must not call zfs"))
    with pytest.raises(ValueError):
        storage.cleanup()


def test_capture_refuses_outstanding_recovery_intent():
    events = []
    storage = Storage(events)
    storage.intent = {"pending": True}
    with pytest.raises(RuntimeError):
        controller.capture(API(events), storage)
    assert events == []


@pytest.mark.parametrize("change", [{"pod_uid": "old"}, {"stopped_at": 99},
                                     {"stopped_at": 111}, {"stopped_at": True},
                                     {"wazuh_databases_gracefully_stopped": False}])
def test_shutdown_marker_rejects_stale_failed_or_wrong_pod(change):
    proof = {"schema": 1, "pod_uid": "current", "stopped_at": 105,
             "wazuh_databases_gracefully_stopped": True}
    controller.check_shutdown(proof, "current", 100, 110)
    proof.update(change)
    with pytest.raises(ValueError):
        controller.check_shutdown(proof, "current", 100, 110)


class Transport:
    def __init__(self, events, fail=None):
        self.events, self.fail = events, fail

    def select_index_capture(self):
        self.events.append("index-preflight")
        if self.fail == "preflight":
            raise ValueError("no fresh native snapshot")
        return {"index_capture": "/fixture/native"}

    def assemble(self, manager, index):
        self.events.append("encrypted-publication")
        assert str(manager) == "/fixture/output/managers/wazuh-fixture"
        assert index == "/fixture/native"
        if self.fail == "publish":
            raise ValueError("encrypted readback failed")
        return {"source_started": 123}


def pipeline_storage(events):
    storage = Storage(events)
    storage.output = Path("/fixture/output")
    storage.capture_id = "wazuh-fixture"
    return storage


def test_native_preflight_failure_prevents_any_quiesce():
    events = []
    with pytest.raises(ValueError):
        controller.pipeline(API(events), pipeline_storage(events), Transport(events, "preflight"))
    assert events == ["index-preflight"]


def test_encryption_follows_recovery_and_export():
    events = []
    receipt = controller.pipeline(API(events), pipeline_storage(events), Transport(events))
    assert events[0] == "index-preflight"
    assert events[-2:] == ["export", "encrypted-publication"]
    assert receipt == {"source_started": 123}


def test_publication_failure_is_failure_after_managers_recover():
    events = []
    storage = pipeline_storage(events)
    with pytest.raises(ValueError):
        controller.pipeline(API(events), storage, Transport(events, "publish"))
    assert storage.intent is None and "ready" in events


@pytest.fixture
def private_transport(tmp_path, monkeypatch):
    import os
    # Preserve real file descriptors/modes; emulate the production root ownership.
    original = os.fstat
    def root_stat(fd):
        fields = list(original(fd)); fields[4] = 0
        return os.stat_result(fields)
    monkeypatch.setattr(os, "fstat", root_stat)
    transport = tmp_path / "transport"
    transport.mkdir(mode=0o700)
    release = transport / ("a" * 40)
    release.mkdir(mode=0o700)
    path = release / "wazuh-backup.py"
    path.write_text("VALUE = 42\n")
    path.chmod(0o500); release.chmod(0o500)
    return path


def test_only_exact_reviewed_private_transport_bytes_execute(private_transport):
    import hashlib
    digest = hashlib.sha256(private_transport.read_bytes()).hexdigest()
    assert getattr(controller.load_transport(private_transport, digest), "VALUE", None) == 42
    with pytest.raises(ValueError):
        controller.load_transport(private_transport, "0" * 64)


@pytest.mark.parametrize("writable", ["file", "directory"])
def test_writable_materialized_transport_is_rejected(private_transport, writable):
    import hashlib
    digest = hashlib.sha256(private_transport.read_bytes()).hexdigest()
    target = private_transport if writable == "file" else private_transport.parent
    target.chmod(0o700)
    with pytest.raises(ValueError):
        controller.load_transport(private_transport, digest)


def test_private_transport_parent_must_be_root_controlled(private_transport):
    import hashlib
    digest = hashlib.sha256(private_transport.read_bytes()).hexdigest()
    private_transport.parent.parent.chmod(0o775)
    with pytest.raises(ValueError, match="Transport parent is not root controlled"):
        controller.load_transport(private_transport, digest)


def test_rescue_keeps_a_fresh_same_boot_intent():
    intent = {"boot_id": "boot", "monotonic": 1000.0}
    assert not controller.rescue_is_stale(intent, "boot", 1000.0 + controller.RESCUE_STALE_SECONDS - 1)


def test_rescue_treats_old_or_foreign_intent_as_stale():
    intent = {"boot_id": "boot", "monotonic": 1000.0}
    assert controller.rescue_is_stale(intent, "boot", 1000.0 + controller.RESCUE_STALE_SECONDS)
    assert controller.rescue_is_stale(intent, "other-boot", 1000.0)


def run_rescue(tmp_path, monkeypatch, events, live_lock=False):
    """Drive main()'s rescue tick against a fresh same-boot intent."""
    import fcntl
    import sys
    import time
    storage = Storage(events)
    storage.state = tmp_path
    storage.intent = {"boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                      "monotonic": 1000.0, "capture_id": "wazuh-fixture"}
    monkeypatch.setattr(controller, "LocalStorage", lambda state, output: storage)
    monkeypatch.setattr(controller, "Cluster", lambda token, ca: API(events))
    monkeypatch.setattr(time, "monotonic", lambda: 2000.0)
    monkeypatch.setattr(sys, "argv", ["capture", "rescue", "--token-file", "token",
                                      "--ca-file", "ca", "--transport-revision", "r",
                                      "--transport-sha256", "s"])
    lock = (tmp_path / "run.lock").open("a")
    if live_lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        controller.main()
    finally:
        lock.close()
    return storage


def test_rescue_recovers_a_fresh_intent_immediately_when_capture_is_inactive(tmp_path, monkeypatch):
    import subprocess
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: pytest.fail("must not stop an inactive capture"))
    events = []
    storage = run_rescue(tmp_path, monkeypatch, events)
    assert events == ["scale:1", "ready", "clear", "cleanup"]
    assert storage.intent is None


def test_rescue_leaves_a_live_capture_holding_the_lock_alone(tmp_path, monkeypatch):
    import subprocess
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: pytest.fail("must not stop a live capture"))
    events = []
    storage = run_rescue(tmp_path, monkeypatch, events, live_lock=True)
    assert events == []
    assert storage.intent is not None


def test_rescue_reclaims_staging_and_owned_snapshot_after_intent_clear(tmp_path, monkeypatch):
    import json
    import subprocess
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    storage.state.mkdir()
    staging = tmp_path / "output" / "managers" / ".incomplete-interrupted"
    staging.mkdir(parents=True)
    record = storage.state / "snapshot.json"
    record.write_text(json.dumps({"name": storage.snapshot_name}))
    commands = []

    def run(args, **kwargs):
        commands.append(args)
        if args[:2] == ["zfs", "list"]:
            return subprocess.CompletedProcess(args, 0, storage.snapshot_name + "\n", "")
        return subprocess.CompletedProcess(args, 0, "", "")

    monkeypatch.setattr(subprocess, "run", run)
    assert controller.reclaim_pending(storage) is True
    assert not staging.exists() and not record.exists()
    assert ["zfs", "destroy", storage.snapshot_name] in commands


def test_rescue_does_not_disturb_an_export_holding_capture_lock(tmp_path, monkeypatch):
    import fcntl
    import json
    import subprocess
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    storage.state.mkdir()
    staging = tmp_path / "output" / "managers" / ".incomplete-live"
    staging.mkdir(parents=True)
    record = storage.state / "snapshot.json"
    record.write_text(json.dumps({"name": storage.snapshot_name}))
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: pytest.fail("must not reclaim during export"))
    with (tmp_path / "output" / "capture.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert controller.reclaim_pending(storage) is False
    assert staging.exists() and record.exists()


def test_slow_successful_recovery_fits_the_configured_unit_budget(monkeypatch):
    import re
    import time
    source = (Path(__file__).parents[2] / "modules/hosts/kepler/wazuh-manager-capture.nix").read_text()
    budget = int(re.search(r'else "(\d+)s"', source).group(1))
    clock = [0.0]
    monkeypatch.setattr(time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(time, "sleep", lambda seconds: clock.__setitem__(0, clock[0] + seconds))
    cluster = object.__new__(controller.Cluster)

    def request(path):
        clock[0] += controller.API_REQUEST_TIMEOUT_SECONDS
        ready = clock[0] >= controller.WAIT_TIMEOUT_SECONDS
        return {"status": {"conditions": [{"type": "Ready", "status": "True"}]}} if ready else {}

    cluster.request = request
    cluster.wait_ready()
    worst = (controller.STOP_TIMEOUT_SECONDS + 2 * controller.API_REQUEST_TIMEOUT_SECONDS
             + controller.WAIT_TIMEOUT_SECONDS + 2 * controller.API_REQUEST_TIMEOUT_SECONDS
             + controller.ZFS_QUERY_TIMEOUT_SECONDS + controller.ZFS_DESTROY_TIMEOUT_SECONDS)
    assert clock[0] <= controller.WAIT_TIMEOUT_SECONDS + 2 * controller.API_REQUEST_TIMEOUT_SECONDS
    assert worst <= budget


def test_incomplete_export_staging_is_discarded(tmp_path):
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    staging = tmp_path / "output" / "managers" / (".incomplete-" + storage.capture_id)
    staging.mkdir(parents=True)
    storage.discard_incomplete()
    assert not staging.exists()


def test_incomplete_staging_does_not_count_as_an_unconsumed_capture(tmp_path, monkeypatch):
    import shutil
    monkeypatch.setattr(shutil, "disk_usage", lambda path: type("Usage", (), {"free": 1 << 40})())
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    managers = tmp_path / "output" / "managers"
    managers.mkdir(parents=True)
    for index in range(3):
        (managers / f".incomplete-capture{index}").mkdir()
    storage.prepare()
    for index in range(3):
        (managers / f"wazuh-capture{index}").mkdir()
    with pytest.raises(RuntimeError, match="Three unconsumed captures"):
        storage.prepare()


def test_prepare_reclaims_interrupted_export_staging(tmp_path, monkeypatch):
    import shutil
    monkeypatch.setattr(shutil, "disk_usage", lambda path: type("Usage", (), {"free": 1 << 40})())
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    managers = tmp_path / "output" / "managers"
    managers.mkdir(parents=True)
    for index in range(2):
        (managers / f".incomplete-orphan{index}").mkdir()
    storage.prepare()
    assert not any(entry.name.startswith(".incomplete-") for entry in managers.iterdir())


def test_cleanup_clears_record_when_snapshot_absence_is_confirmed(tmp_path, monkeypatch):
    import json
    import subprocess
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    storage.state.mkdir()
    record = storage.state / "snapshot.json"
    record.write_text(json.dumps({"name": storage.snapshot_name}))
    monkeypatch.setattr(
        subprocess, "run",
        lambda args, **kwargs: subprocess.CompletedProcess(
            args, 1, "", "cannot open 'fast-pool/data@wazuh-x': dataset does not exist\n"),
    )
    storage.cleanup()
    assert not record.exists()


def test_cleanup_keeps_record_when_the_query_fails(tmp_path, monkeypatch):
    import json
    import subprocess
    storage = controller.LocalStorage(tmp_path / "state", tmp_path / "output")
    storage.state.mkdir()
    record = storage.state / "snapshot.json"
    record.write_text(json.dumps({"name": storage.snapshot_name}))
    monkeypatch.setattr(
        subprocess, "run",
        lambda args, **kwargs: subprocess.CompletedProcess(args, 1, "", "permission denied\n"),
    )
    with pytest.raises(RuntimeError, match="Cannot establish task snapshot existence"):
        storage.cleanup()
    assert record.exists()


def test_freshness_uses_completed_backup_source_time(tmp_path):
    path = tmp_path / "wazuh-recovery.prom"
    controller.write_freshness(path, {"source_started": 123})
    assert path.exists(), "verified backup freshness was not published"
    assert path.read_text() == "wazuh_recovery_source_timestamp_seconds 123\n"
    assert path.stat().st_mode & 0o777 == 0o644


def test_invalid_freshness_does_not_replace_prior_evidence(tmp_path):
    path = tmp_path / "wazuh-recovery.prom"
    path.write_text("old")
    with pytest.raises(ValueError):
        controller.write_freshness(path, {"source_started": True})
    assert path.read_text() == "old"


@pytest.mark.parametrize("index_changed", [False, True])
def test_indexer_backing_volume_must_still_match_reviewed_binding(index_changed):
    cluster = object.__new__(controller.Cluster)
    def request(path):
        if "applications/wazuh" in path:
            return delegation()
        if controller.BINDINGS["indexer"] in path:
            if index_changed:
                return {"metadata": {"name": "replacement"}}
            uid = controller.BINDINGS["indexer"]
            return {"metadata": {"name": "pvc-" + uid}, "status": {"phase": "Bound"},
                    "spec": {"claimRef": {"uid": uid, "name": "wazuh-indexer-wazuh-indexer-0", "namespace": "wazuh"},
                             "csi": {"driver": "nfs.csi.k8s.io", "volumeHandle": f"10.250.0.1#bulk/k8s#pvc-{uid}##",
                                     "volumeAttributes": {"server": "10.250.0.1", "share": "/bulk/k8s", "subdir": "pvc-" + uid}}}}
        for role in controller.MANAGERS:
            claim, volume = binding(role)
            if path.endswith("/pvc-" + controller.BINDINGS[role]):
                return volume
            if "persistentvolumeclaims/" in path and role in path:
                return claim
            if path == cluster.scale_path(role):
                return {"spec": {"replicas": 1}, "status": {"replicas": 1}}
            if path == cluster.pod_path(role):
                return {"metadata": {"uid": "uid-" + role},
                        "status": {"conditions": [{"type": "Ready", "status": "True"}]},
                        "spec": {"containers": [{"image": "fixture@" + controller.MANAGER_DIGEST}]}}
        raise AssertionError("unexpected API request")
    cluster.request = request
    if index_changed:
        with pytest.raises(ValueError):
            cluster.preflight()
    else:
        assert cluster.preflight() == {"master": "uid-master", "worker": "uid-worker"}
