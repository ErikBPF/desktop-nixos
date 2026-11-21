"""Bounded Kepler capture of the two Wazuh manager PVCs.

The run lock belongs to systemd's root-only state directory. Recovery never
requires a successful backup, only the intent durably written before scaling.
"""


def recover(api, storage):
    if storage.read_intent() is not None:
        api.scale(1)
        api.wait_ready()
        storage.clear_intent()


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
    storage.export(identities)


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

    def __init__(self, token_file, ca_file):
        import ssl
        from pathlib import Path
        self.token_file = Path(token_file)
        self.context = ssl.create_default_context(cafile=ca_file)

    def request(self, path, replicas=None):
        import json
        import urllib.error
        import urllib.request
        token = self.token_file.read_text().strip()
        if not token or "\n" in token:
            raise ValueError("Missing or malformed runtime token")
        payload = None if replicas is None else json.dumps({"spec": {"replicas": replicas}}).encode()
        request = urllib.request.Request(
            "https://192.168.10.245:6443" + path, data=payload,
            method="GET" if replicas is None else "PATCH",
            headers={"Authorization": "Bearer " + token,
                     "Content-Type": "application/merge-patch+json"},
        )
        try:
            with urllib.request.urlopen(request, context=self.context, timeout=10) as response:
                data = response.read(1_048_577)
                if len(data) > 1_048_576:
                    raise ValueError("API response exceeds metadata bound")
                return json.loads(data)
        except urllib.error.HTTPError as error:
            if error.code == 404 and replicas is None:
                return None
            raise RuntimeError(f"Kubernetes API rejected named request: HTTP {error.code}") from None

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
                    or pod.get("metadata", {}).get("deletionTimestamp")
                    or not self.ready(pod)
                    or not any(c.get("image", "").endswith("@" + MANAGER_DIGEST)
                               for c in pod.get("spec", {}).get("containers", []))):
                raise ValueError("Both named managers must be healthy at one replica")
            identities[role] = pod["metadata"]["uid"]
        return identities

    @staticmethod
    def ready(pod):
        return bool(pod) and any(c.get("type") == "Ready" and c.get("status") == "True"
                                for c in pod.get("status", {}).get("conditions", []))

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
        deadline = time.monotonic() + 120
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

    def prepare(self):
        import shutil
        # Whole-dataset snapshot COW and archive space must both have headroom.
        minimum = 24 * 1024**3
        if shutil.disk_usage("/fast").free < minimum or shutil.disk_usage(self.output).free < minimum:
            raise RuntimeError("Insufficient capture headroom")
        if len(list((self.output / "managers").iterdir())) >= 3:
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
        import re
        import subprocess
        path = self.state / "snapshot.json"
        if not path.exists():
            return
        name = json.loads(path.read_text())["name"]
        if not re.fullmatch(r"fast-pool/data@wazuh-[0-9a-f]{32}", name):
            raise ValueError("Refusing cleanup of an unowned snapshot name")
        exists = subprocess.run(["zfs", "list", "-H", "-t", "snapshot", "-o", "name", name],
                                capture_output=True, timeout=10)
        if exists.returncode == 0:
            subprocess.run(["zfs", "destroy", name], check=True, timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            raise RuntimeError("Cannot establish task snapshot existence; retain cleanup record")
        path.unlink()

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
            return
        boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        if intent.get("boot_id") == boot_id and time.monotonic() - intent["monotonic"] < 180:
            return
        subprocess.run(["systemctl", "stop", "wazuh-manager-capture.service"],
                       check=True, timeout=15, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with (state / "run.lock").open("a") as run_lock:
        fcntl.flock(run_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        cluster = Cluster(arguments.token_file, arguments.ca_file)
        if arguments.mode != "capture":
            recover(cluster, storage)
            storage.cleanup()
            return
        with (output / "capture.lock").open("a") as bundle_lock:
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
