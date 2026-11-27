"""Bounded Kepler capture of the two Wazuh manager PVCs.

The run lock belongs to systemd's root-only state directory. Recovery never
requires a successful backup, only the intent durably written before scaling.
"""


# Recovery and rescue deadlines. The unit budget is 300 s: a 15 s service stop,
# two 10 s scale requests, a 120 s readiness window plus one 20 s poll pair,
# a 10 s snapshot existence check and a 30 s destroy. Each API request has one
# 10 s wall-clock deadline that covers connect, request send, response headers
# and body. A watchdog closes the socket at that deadline, because a socket
# timeout bounds one wait, not a trickling header or body.
STOP_TIMEOUT_SECONDS = 15
API_REQUEST_TIMEOUT_SECONDS = 10
WAIT_TIMEOUT_SECONDS = 120
ZFS_QUERY_TIMEOUT_SECONDS = 10
ZFS_DESTROY_TIMEOUT_SECONDS = 30

# A same-boot intent older than this is treated as abandoned. Rescue may stop
# the unit and run the full recovery path above, so the watchdog sits above
# those deadlines and below the unit's 40-minute capture budget.
RESCUE_STALE_SECONDS = 30 * 60


def rescue_is_stale(intent, boot_id, now):
    return intent.get("boot_id") != boot_id or now - intent["monotonic"] >= RESCUE_STALE_SECONDS


def recover(api, storage):
    if storage.read_intent() is not None:
        api.scale(1)
        api.wait_ready()
        storage.clear_intent()


def reclaim_pending(storage):
    """Reclaim interrupted storage when no capture intent survives.

    An explicit stop during export bypasses Python cleanup, leaving staging and
    a recorded snapshot with no intent to gate rescue. Both locks are taken
    without blocking: a live export owns capture.lock and any active controller
    owns run.lock, so a false result means "leave it alone".
    """
    import fcntl
    with (storage.state / "run.lock").open("a") as run_lock:
        try:
            fcntl.flock(run_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        with (storage.output / "capture.lock").open("a") as export_lock:
            try:
                fcntl.flock(export_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return False
            storage.reclaim_incomplete()
            storage.cleanup()
            return True


def capture(api, storage):
    if storage.read_intent() is not None:
        raise RuntimeError("Unrecovered capture intent; recovery must run first")
    identities = api.preflight()
    storage.prepare()
    storage.save_intent(identities)
    try:
        api.scale(0)
        api.wait_stopped()
        storage.verify_shutdown(identities)
        storage.snapshot()
    finally:
        recover(api, storage)
    try:
        storage.export(identities)
    except BaseException:
        # The partial directory is never consumable and counts against the
        # three-capture budget, so a failure must not leave it behind.
        storage.discard_incomplete()
        raise


def pipeline(api, storage, transport):
    selected = transport.select_index_capture()
    capture(api, storage)
    return transport.assemble(storage.output / "managers" / storage.capture_id,
                              selected["index_capture"])


def load_transport(path, expected_sha256):
    import hashlib
    import os
    import re
    import stat
    import types
    from pathlib import Path
    path = Path(path)
    if (path.name != "wazuh-backup.py" or not re.fullmatch(r"[0-9a-f]{40}", path.parent.name)
            or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256)):
        raise ValueError("Invalid reviewed transport identity")
    parent = os.open(path.parent.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(parent)
        if info.st_uid != 0 or info.st_mode & 0o022:
            raise ValueError("Transport parent is not root controlled")
        release = os.open(path.parent.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            info = os.fstat(release)
            if info.st_uid != 0 or info.st_mode & 0o222:
                raise ValueError("Transport release is writable or not root owned")
            fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=release)
            with os.fdopen(fd, "rb") as source:
                info = os.fstat(source.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o222:
                    raise ValueError("Transport file is writable or not root owned")
                data = source.read(131073)
        finally:
            os.close(release)
    finally:
        os.close(parent)
    if len(data) > 131072 or hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError("Materialized transport differs from reviewed SHA256")
    module = types.ModuleType("wazuh_published_transport")
    # Execute the verified bytes, not a second pathname read or a cached pyc.
    exec(compile(data, str(path), "exec"), module.__dict__)
    return module


def write_freshness(path, receipt):
    import os
    import tempfile
    import time
    stamp = receipt.get("source_started")
    if type(stamp) is not int or not 0 < stamp <= int(time.time()):
        raise ValueError("Invalid successful backup source timestamp")
    fd, temporary = tempfile.mkstemp(prefix=".wazuh-recovery-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(f"wazuh_recovery_source_timestamp_seconds {stamp}\n")
            output.flush()
            os.fchmod(output.fileno(), 0o644)
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


MANAGERS = ("master", "worker")
MANAGER_DIGEST = "sha256:8665c9807a5765253c79e4b072a1b7462c997bd69be949118a8d82ce44dd33e9"
AUTHD_FINGERPRINT = "3D:53:33:FB:58:6F:22:DA:2A:72:71:23:9F:F4:3A:EB:B0:F9:20:3F:35:2D:0A:66:76:94:00:B4:34:9B:05:27".replace(":", "")
BINDINGS = {
    "master": "24bb0968-7b98-463a-af73-249a186fddc8",
    "worker": "f310f72b-ce47-44df-929f-1fdf16c145be",
    "indexer": "4c197eed-4b28-431b-bb4c-99e17fc3d460",
}


def check_delegation(application):
    spec = application.get("spec", {})
    if "RespectIgnoreDifferences=true" not in spec.get("syncPolicy", {}).get("syncOptions", []):
        raise ValueError("Argo does not delegate replica reconciliation")
    rules = spec.get("ignoreDifferences", [])
    for role in MANAGERS:
        expected = {"group": "apps", "kind": "StatefulSet", "namespace": "wazuh",
                    "name": f"wazuh-manager-{role}", "jsonPointers": ["/spec/replicas"]}
        if expected not in rules:
            raise ValueError("Missing exact manager replica delegation")


def check_volume(role, volume):
    uid = BINDINGS[role]
    name = ("wazuh-indexer-wazuh-indexer-0" if role == "indexer"
            else f"wazuh-manager-{role}-wazuh-manager-{role}-0")
    root = "/bulk/k8s" if role == "indexer" else "/fast/k8s"
    try:
        valid = (volume["metadata"]["name"] == f"pvc-{uid}"
                 and volume["status"]["phase"] == "Bound"
                 and volume["spec"]["claimRef"]["uid"] == uid
                 and volume["spec"]["claimRef"]["name"] == name
                 and volume["spec"]["claimRef"]["namespace"] == "wazuh"
                 and volume["spec"]["csi"]["driver"] == "nfs.csi.k8s.io"
                 and volume["spec"]["csi"]["volumeHandle"] == f"10.250.0.1#{root[1:]}#pvc-{uid}##"
                 and all(volume["spec"]["csi"]["volumeAttributes"].get(key) == value
                         for key, value in {"server": "10.250.0.1", "share": root,
                                            "subdir": f"pvc-{uid}"}.items()))
    except KeyError:
        valid = False
    if not valid:
        raise ValueError("Wazuh backing volume differs from reviewed binding")


def check_binding(role, claim, volume):
    uid = BINDINGS[role]
    name = f"wazuh-manager-{role}-wazuh-manager-{role}-0"
    try:
        valid = (claim["metadata"]["uid"] == uid
                 and claim["metadata"]["name"] == name
                 and claim["status"]["phase"] == "Bound"
                 and claim["spec"]["volumeName"] == f"pvc-{uid}")
    except KeyError:
        valid = False
    if not valid:
        raise ValueError("Wazuh PVC differs from reviewed identity")
    check_volume(role, volume)


class Cluster:
    """Only named GETs and the two scale PATCHes; token never reaches argv."""

    endpoint = "https://192.168.10.245:6443"

    def __init__(self, token_file, ca_file):
        import ssl
        from pathlib import Path
        self.token_file = Path(token_file)
        self.context = ssl.create_default_context(cafile=ca_file)

    def request(self, path, replicas=None):
        import http.client
        import json
        import socket
        import threading
        import time
        import urllib.parse
        token = self.token_file.read_text().strip()
        if not token or "\n" in token:
            raise ValueError("Missing or malformed runtime token")
        payload = None if replicas is None else json.dumps({"spec": {"replicas": replicas}}).encode()
        headers = {"Authorization": "Bearer " + token,
                   "Content-Type": "application/merge-patch+json"}
        endpoint = urllib.parse.urlsplit(self.endpoint)
        deadline = time.monotonic() + API_REQUEST_TIMEOUT_SECONDS
        message = f"API request exceeded its {API_REQUEST_TIMEOUT_SECONDS} s deadline"
        timed_out = threading.Event()
        finished = threading.Event()
        connection = None
        sock = None
        timer = None
        try:
            remaining = max(deadline - time.monotonic(), 0.001)
            if endpoint.scheme == "https":
                connection = http.client.HTTPSConnection(
                    endpoint.hostname, endpoint.port, timeout=remaining, context=self.context)
            else:
                connection = http.client.HTTPConnection(
                    endpoint.hostname, endpoint.port, timeout=remaining)

            def expire():
                timed_out.set()
                # Close once a live socket exists. A connect or TLS wrap publishes
                # it only when it returns, so poll briefly instead of closing
                # nothing and letting the transport continue.
                while not finished.is_set():
                    current = sock if sock is not None else connection.sock
                    if current is not None:
                        # A close alone does not reliably interrupt a blocked
                        # recv on Linux; shutdown does. A detached socket reports
                        # EBADF, so keep looking for its replacement.
                        try:
                            current.shutdown(socket.SHUT_RDWR)
                        except OSError:
                            current = None
                        if current is not None:
                            try:
                                current.close()
                            except OSError:
                                pass
                            return
                    finished.wait(0.01)

            # Planned from the deadline, and cancelled and joined in finally, so
            # a finished request never leaves a timer behind.
            timer = threading.Timer(max(deadline - time.monotonic(), 0), expire)
            timer.daemon = True
            timer.start()
            # Own the connect: http.client's HTTPS connect detaches the raw socket
            # before the handshake, so the watchdog could not reach it and the
            # handshake would get a fresh timeout. Publish the live TLS socket
            # first and give the handshake only the time that is left.
            sock = socket.create_connection(
                (endpoint.hostname, endpoint.port),
                timeout=max(deadline - time.monotonic(), 0.001))
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            if endpoint.scheme == "https":
                sock = self.context.wrap_socket(
                    sock, server_hostname=endpoint.hostname, do_handshake_on_connect=False)
                sock.settimeout(max(deadline - time.monotonic(), 0.001))
                sock.do_handshake()
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            sock.settimeout(remaining)
            # A non-None sock makes http.client skip its own unsafe connect.
            connection.sock = sock
            connection.request("GET" if replicas is None else "PATCH", path,
                               body=payload, headers=headers)
            response = connection.getresponse()
            if response.status == 404 and replicas is None:
                return None
            if not 200 <= response.status < 300:
                raise RuntimeError(
                    f"Kubernetes API rejected named request: HTTP {response.status}")
            body = bytearray()
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError
                # The watchdog interrupts a blocked read at the deadline; the
                # connect timeout already bounds any single wait.
                chunk = response.read1(65_536)
                if not chunk:
                    break
                body.extend(chunk)
                if len(body) > 1_048_576:
                    raise ValueError("API response exceeds metadata bound")
            return json.loads(body)
        except TimeoutError:
            raise TimeoutError(message) from None
        except (OSError, http.client.HTTPException, ValueError):
            # The watchdog forces socket/read failures; surface one deadline error.
            if timed_out.is_set():
                raise TimeoutError(message) from None
            raise
        finally:
            finished.set()
            if timer is not None:
                timer.cancel()
                timer.join()
            if sock is not None:
                try:
                    sock.close()
                except OSError:
                    pass
            if connection is not None:
                connection.close()

    @staticmethod
    def pod_path(role):
        return f"/api/v1/namespaces/wazuh/pods/wazuh-manager-{role}-0"

    @staticmethod
    def scale_path(role):
        return f"/apis/apps/v1/namespaces/wazuh/statefulsets/wazuh-manager-{role}/scale"

    def preflight(self):
        check_delegation(self.request("/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/wazuh") or {})
        check_volume("indexer", self.request(f"/api/v1/persistentvolumes/pvc-{BINDINGS['indexer']}") or {})
        identities = {}
        for role in MANAGERS:
            name = f"wazuh-manager-{role}-wazuh-manager-{role}-0"
            check_binding(role,
                          self.request(f"/api/v1/namespaces/wazuh/persistentvolumeclaims/{name}") or {},
                          self.request(f"/api/v1/persistentvolumes/pvc-{BINDINGS[role]}") or {})
            scale = self.request(self.scale_path(role)) or {}
            pod = self.request(self.pod_path(role)) or {}
            if (scale.get("spec", {}).get("replicas") != 1
                    or scale.get("status", {}).get("replicas") != 1
                    or not self.ready(pod)
                    or not any(c.get("image", "").endswith("@" + MANAGER_DIGEST)
                               for c in pod.get("spec", {}).get("containers", []))):
                raise ValueError("Both named managers must be healthy at one replica")
            identities[role] = pod["metadata"]["uid"]
        return identities

    @staticmethod
    def ready(pod):
        return (bool(pod)
                and not pod.get("metadata", {}).get("deletionTimestamp")
                and any(c.get("type") == "Ready" and c.get("status") == "True"
                        for c in pod.get("status", {}).get("conditions", [])))

    def scale(self, replicas):
        failures = []
        for role in MANAGERS:
            try:
                self.request(self.scale_path(role), replicas)
            except Exception:
                failures.append(role)
        if failures:
            raise RuntimeError("Scale failed for " + ", ".join(failures))

    def wait(self, ready):
        import time
        deadline = time.monotonic() + WAIT_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            pods = [self.request(self.pod_path(role)) for role in MANAGERS]
            if all(self.ready(pod) for pod in pods) if ready else all(pod is None for pod in pods):
                return
            time.sleep(2)
        raise TimeoutError("Named manager readiness/termination deadline exceeded")

    def wait_stopped(self):
        self.wait(False)

    def wait_ready(self):
        self.wait(True)


def atomic_json(path, value):
    """Replace private state and persist its directory before external mutation."""
    import json
    import os
    import tempfile
    fd, temporary = tempfile.mkstemp(prefix=".capture-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def check_shutdown(proof, uid, started, now):
    if (proof.get("schema") != 1 or proof.get("pod_uid") != uid
            or proof.get("wazuh_databases_gracefully_stopped") is not True
            or type(proof.get("stopped_at")) is not int
            or not started <= proof["stopped_at"] <= now):
        raise ValueError("Missing current graceful Wazuh shutdown proof")


class LocalStorage:
    def __init__(self, state, output):
        import time
        import uuid
        from pathlib import Path
        self.state = Path(state)
        self.output = Path(output)
        self.started = int(time.time())
        self.capture_id = "wazuh-" + uuid.uuid4().hex
        self.snapshot_name = "fast-pool/data@" + self.capture_id

    def reclaim_incomplete(self, keep=None):
        import shutil
        managers = self.output / "managers"
        if not managers.exists():
            return
        for entry in managers.iterdir():
            if entry.name.startswith(".incomplete-") and entry.name != keep:
                shutil.rmtree(entry, ignore_errors=True)

    def prepare(self):
        import shutil
        # Interrupted exports leave staging that no exception handler reclaimed.
        self.reclaim_incomplete(".incomplete-" + self.capture_id)
        # Whole-dataset snapshot COW and archive space must both have headroom.
        minimum = 24 * 1024**3
        if shutil.disk_usage("/fast").free < minimum or shutil.disk_usage(self.output).free < minimum:
            raise RuntimeError("Insufficient capture headroom")
        consumed = [
            entry for entry in (self.output / "managers").iterdir()
            if not entry.name.startswith(".incomplete-")
        ]
        if len(consumed) >= 3:
            raise RuntimeError("Three unconsumed captures; transport must drain them before capture")
        if (self.state / "snapshot.json").exists():
            raise RuntimeError("Previous task snapshot needs recovery cleanup")

    def save_intent(self, identities):
        import time
        from pathlib import Path
        atomic_json(self.state / "intent.json", {"schema": 1, "started": self.started,
                                                "monotonic": time.monotonic(),
                                                "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                                                "capture_id": self.capture_id,
                                                "identities": identities})

    def read_intent(self):
        import json
        path = self.state / "intent.json"
        return json.loads(path.read_text()) if path.exists() else None

    def clear_intent(self):
        import os
        (self.state / "intent.json").unlink()
        directory = os.open(self.state, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)

    def verify_shutdown(self, identities):
        import json
        import time
        from pathlib import Path
        for role in MANAGERS:
            marker = Path(f"/fast/k8s/pvc-{BINDINGS[role]}/wazuh/var/ossec/queue/.host-integrity-stop.json")
            proof = json.loads(marker.read_text())
            check_shutdown(proof, identities[role], self.started, int(time.time()))

    def snapshot(self):
        import subprocess
        # Persist the exact name first: rescue may destroy only this task's name.
        atomic_json(self.state / "snapshot.json", {"name": self.snapshot_name})
        subprocess.run(["zfs", "snapshot", self.snapshot_name], check=True, timeout=30,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def cleanup(self):
        import json
        import os
        import re
        import subprocess
        path = self.state / "snapshot.json"
        if not path.exists():
            return
        name = json.loads(path.read_text())["name"]
        if not re.fullmatch(r"fast-pool/data@wazuh-[0-9a-f]{32}", name):
            raise ValueError("Refusing cleanup of an unowned snapshot name")
        exists = subprocess.run(["zfs", "list", "-H", "-t", "snapshot", "-o", "name", name],
                                capture_output=True, text=True, timeout=ZFS_QUERY_TIMEOUT_SECONDS)
        if exists.returncode == 0:
            subprocess.run(["zfs", "destroy", name], check=True, timeout=ZFS_DESTROY_TIMEOUT_SECONDS,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif not any(token in (exists.stderr or "").lower() for token in ("does not exist", "no such")):
            raise RuntimeError("Cannot establish task snapshot existence; retain cleanup record")
        # Absence is confirmed (or the destroy succeeded): drop the record durably.
        path.unlink()
        directory = os.open(self.state, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)

    def discard_incomplete(self):
        import shutil
        shutil.rmtree(self.output / "managers" / (".incomplete-" + self.capture_id), ignore_errors=True)

    def export(self, identities):
        import hashlib
        import os
        import resource
        import subprocess
        import time
        from pathlib import Path
        directory = self.output / "managers" / (".incomplete-" + self.capture_id)
        directory.mkdir(mode=0o700, parents=True)
        checksums = {}
        intervals = {}
        remaining = 12 * 1024**3
        for role in MANAGERS:
            archive = directory / f"manager-{role}.tar"
            source = Path(f"/fast/.zfs/snapshot/{self.capture_id}/k8s/pvc-{BINDINGS[role]}")
            started = int(time.time())
            def limit():
                resource.setrlimit(resource.RLIMIT_FSIZE, (remaining, remaining))
            with archive.open("xb") as output:
                os.chmod(archive, 0o600)
                subprocess.run(["tar", "--one-file-system", "--numeric-owner", "-cf", "-", "-C", str(source), "."],
                               stdout=output, stderr=subprocess.DEVNULL, timeout=180, check=True,
                               preexec_fn=limit)
                output.flush()
                os.fsync(output.fileno())
            remaining -= archive.stat().st_size
            with archive.open("rb") as data:
                checksums[archive.name] = hashlib.file_digest(data, "sha256").hexdigest()
            intervals[archive.name] = {"started": started, "completed": int(time.time())}
        snapshot_root = Path(f"/fast/.zfs/snapshot/{self.capture_id}/k8s")
        for role in MANAGERS:
            old = snapshot_root / f"pvc-{BINDINGS[role]}/wazuh/var/ossec/etc/client.keys"
            current = Path(f"/fast/k8s/pvc-{BINDINGS[role]}/wazuh/var/ossec/etc/client.keys")
            with old.open("rb") as left, current.open("rb") as right:
                if hashlib.file_digest(left, "sha256").digest() != hashlib.file_digest(right, "sha256").digest():
                    raise ValueError("Manager enrollment identities changed during capture")
        cert = snapshot_root / f"pvc-{BINDINGS['master']}/wazuh/var/ossec/etc/sslmanager.cert"
        result = subprocess.run(["openssl", "x509", "-in", str(cert), "-noout", "-fingerprint", "-sha256"],
                                capture_output=True, check=True, timeout=10)
        fingerprint = result.stdout.decode().strip().split("=", 1)[-1].replace(":", "")
        if fingerprint != AUTHD_FINGERPRINT:
            raise ValueError("Enrollment public certificate differs from approved pin")
        atomic_json(directory / "manager-capture.json", {
            "schema": 1, "capture_id": self.capture_id, "started": self.started,
            "completed": int(time.time()), "sha256": checksums, "intervals": intervals,
            "pod_uids": identities, "wazuh_databases_gracefully_stopped": True,
            "managers_recovered": True,
            "filebeat_consistency": "not-proven", "identities_preserved": True,
            "manager_image_digest": MANAGER_DIGEST,
            "authd_sha256": AUTHD_FINGERPRINT,
        })
        published = self.output / "managers" / self.capture_id
        os.rename(directory, published)
        parent = os.open(published.parent, os.O_DIRECTORY)
        try:
            os.fsync(parent)
        finally:
            os.close(parent)
        atomic_json(self.output / "current-manager.json", {"capture_id": self.capture_id})


def main():
    import argparse
    import fcntl
    import os
    import subprocess
    import time
    from pathlib import Path
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("capture", "recover", "rescue"))
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--ca-file", required=True)
    parser.add_argument("--transport-revision", required=True)
    parser.add_argument("--transport-sha256", required=True)
    arguments = parser.parse_args()
    os.umask(0o077)
    state = Path("/var/lib/wazuh-manager-capture")
    output = Path("/bulk/backups/wazuh")
    storage = LocalStorage(state, output)
    if arguments.mode == "rescue":
        intent = storage.read_intent()
        if intent is None:
            # Intent clears before archive export, so an interrupted export
            # leaves reclaimable storage with no intent to gate this path.
            reclaim_pending(storage)
            return
        boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        if rescue_is_stale(intent, boot_id, time.monotonic()):
            subprocess.run(["systemctl", "stop", "wazuh-manager-capture.service"],
                           check=True, timeout=STOP_TIMEOUT_SECONDS, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # A fresh intent can still need recovery: a stop, restart or deployment
        # after scale-down kills Python before its finally block and does not
        # fail the unit, so OnFailure never runs. The run lock below decides:
        # busy means a live capture, free means an interrupted one.
    with (storage.state / "run.lock").open("a") as run_lock:
        try:
            fcntl.flock(run_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if arguments.mode == "rescue":
                return
            raise
        cluster = Cluster(arguments.token_file, arguments.ca_file)
        if arguments.mode != "capture":
            recover(cluster, storage)
            storage.cleanup()
            return
        with (storage.output / "capture.lock").open("a") as bundle_lock:
            fcntl.flock(bundle_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                transport = load_transport(state / "transport" / arguments.transport_revision / "wazuh-backup.py",
                                           arguments.transport_sha256)
                receipt = pipeline(cluster, storage, transport)
                write_freshness(Path("/var/lib/node-exporter-textfile/wazuh-recovery.prom"), receipt)
            finally:
                storage.cleanup()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never dump API bodies, tokens, local private paths or archive contents.
        import sys
        print(f"Wazuh capture failed ({type(error).__name__}); inspect private state and recovery unit", file=sys.stderr)
        sys.exit(1)
