#!/usr/bin/env bash
set -euo pipefail
exec python3 - "$0" "$@" <<'PY'
import contextlib
import filecmp
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import shlex
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import tarfile
import tempfile
import threading
import time

ROOT = Path("/home/erik/homelab/apps")
NAMES = ("hermes-argus", "hermes-agent")
WRITERS = [f"docker-{name}.service" for name in NAMES]
TIMERS = [f"{name}-healthcheck.timer" for name in NAMES]
HEALTH = [f"{name}-healthcheck.service" for name in NAMES]
TAG = "discovery-hermes-state-v1"
ARCHIVE = "hermes-state-v1.tar"
LIMIT = 600
MAX_ARCHIVE = 64 * 1024**3
FRAME_END = b"\nHERMES1 END\n"
PHASE = "supervisor-preflight"
REMOTE_DIAGNOSTIC = None
PHASES = {"credential-preflight", "repository-preflight", "supervisor-preflight", "quiesce", "archive", "snapshot", "snapshot-validation", "isolated-restore", "integrity", "recovery", "remote-unobserved"}
ERROR_CLASSES = {"CalledProcessError", "TimeoutExpired", "TimeoutError", "PermissionError", "FileNotFoundError", "BrokenPipeError", "OSError", "ValueError", "RuntimeError", "JSONDecodeError", "OperationalError", "DatabaseError", "IntegrityError", "KeyboardInterrupt"}


def diagnostic(error):
    name = type(error).__name__
    result = {"phase": PHASE if PHASE in PHASES else "remote-unobserved",
              "class": name if name in ERROR_CLASSES else "OtherError"}
    if isinstance(error, subprocess.CalledProcessError) and type(error.returncode) is int:
        result["returncode"] = error.returncode
    return result


def run(args, **kw):
    return subprocess.run(args, check=True, timeout=LIMIT,
                          stderr=subprocess.DEVNULL, **kw)


def valid_id(snapshot):
    if not re.fullmatch(r"[0-9a-f]{64}", snapshot):
        raise ValueError("invalid snapshot ID")
    return snapshot


def states():
    result = {}
    for name in TIMERS + HEALTH + WRITERS:
        data = run(["systemctl", "show", name, "-p", "LoadState", "-p", "ActiveState"],
                   stdout=subprocess.PIPE).stdout.decode().splitlines()
        values = dict(line.split("=", 1) for line in data)
        load, active = values.get("LoadState"), values.get("ActiveState")
        if load == "not-found" and name in TIMERS + HEALTH:
            result[name] = "absent"
        elif load == "loaded" and active in ("active", "inactive"):
            result[name] = active
        else:
            raise ValueError("unexpected unit state")
    for timer, health in zip(TIMERS, HEALTH):
        if (result[timer] == "absent") != (result[health] == "absent"):
            raise ValueError("unexpected health unit absence")
    return result


def unit(action, name):
    run(["systemctl", action, name], stdout=subprocess.DEVNULL)


def stopped():
    if any(value == "active" for value in states().values()):
        raise ValueError("units not quiesced")


def preflight():
    for tool in ("tar", "systemctl"):
        if not shutil.which(tool):
            raise ValueError("required remote tool unavailable")
    for name in NAMES:
        path = ROOT / name
        for parent in [path, *path.parents]:
            if parent.is_symlink() or not parent.is_dir():
                raise ValueError("invalid source ancestor")
        for filename in ("state.db", "state.db-wal", "state.db-shm", "state.db-journal"):
            db = path / filename
            if db.is_symlink() or (filename == "state.db" or db.exists()) and not db.is_file():
                raise ValueError("state database must be regular")
    # Ordinary Btrfs subvolumes are included. Other nested mounts are not.
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        before, after = line.split(" - ", 1)
        mount = before.split()[4]
        mount = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), mount)
        for name in NAMES:
            source = str(ROOT / name)
            if mount == source or mount.startswith(source + "/"):
                if after.split()[0] != "btrfs":
                    raise ValueError("unexpected source mount")


def send_archive():
    with tempfile.TemporaryDirectory(prefix="hermes-state-frame-") as tmp:
        archive = Path(tmp) / ARCHIVE
        run(["tar", "--format=pax", "-C", str(ROOT), "-cpf", str(archive), *NAMES], stdout=subprocess.DEVNULL)
        length = archive.stat().st_size
        if not 0 < length <= MAX_ARCHIVE:
            raise ValueError("archive frame too large")
        signal.alarm(LIMIT)
        sys.stdout.buffer.write(f"HERMES1 {length}\n".encode("ascii"))
        with archive.open("rb") as stream:
            shutil.copyfileobj(stream, sys.stdout.buffer)
        sys.stdout.buffer.write(FRAME_END)
        sys.stdout.buffer.flush()


def frame_backup(stream, restic, directory):
    global PHASE
    deadline = time.monotonic() + LIMIT
    def ready(fd, writing=False):
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([] if writing else [fd], [fd] if writing else [], [], remaining)[bool(writing)]:
            raise TimeoutError("archive frame deadline")
    def read(count):
        ready(stream.fileno())
        value = os.read(stream.fileno(), count)
        if not value:
            raise ValueError("truncated archive frame")
        return value
    header = b""
    while not header.endswith(b"\n"):
        if len(header) >= 40:
            raise ValueError("invalid archive frame")
        header += read(1)
    if not re.fullmatch(rb"HERMES1 [1-9][0-9]{0,11}\n", header):
        raise ValueError("invalid archive frame")
    count = int(header.split()[1])
    if count > MAX_ARCHIVE:
        raise ValueError("archive frame too large")
    PHASE = "snapshot"  # Valid frame observed; archive transport now established.
    result_file = Path(directory) / "backup-result"
    with result_file.open("w+b") as result:
        process = subprocess.Popen(restic + ["backup", "--stdin", "--stdin-filename", ARCHIVE, "--tag", TAG, "--json"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        overflow = []
        def capture():
            count = 0
            try:
                while data := process.stdout.read(65536):
                    count += len(data)
                    if count <= 16 * 1024**2:
                        result.write(data)
                    elif not overflow:
                        overflow.append(True)
            except BaseException:
                overflow.append(True)
            finally:
                process.stdout.close()
        reader = threading.Thread(target=capture, daemon=True)
        reader.start()  # Drain even after cap; no progress-output pipe deadlock.
        try:
            while count:
                data = read(min(count, 65536))
                count -= len(data)
                while data:
                    ready(process.stdin.fileno(), True)
                    written = os.write(process.stdin.fileno(), data[:4096])
                    data = data[written:]
            ending = b""
            while len(ending) < len(FRAME_END):
                ending += read(len(FRAME_END) - len(ending))
            if ending != FRAME_END:
                raise ValueError("invalid archive frame ending")
            process.stdin.close()  # Parent-controlled EOF, independent of SSH FD.
            if process.wait(timeout=LIMIT) != 0:
                raise ValueError("encrypted backup failed")
        finally:
            process.stdin.close()
            if process.poll() is None:
                process.kill()  # Only local Restic; never kill recovery supervisor.
                process.wait(timeout=30)
            reader.join(timeout=30)
        if reader.is_alive() or overflow:
            raise ValueError("backup result too large")
        result.seek(0)
        summaries = [json.loads(line) for line in result if json.loads(line).get("message_type") == "summary"]
    if len(summaries) != 1:
        raise ValueError("backup result missing")
    return valid_id(summaries[0]["snapshot_id"])


def extract(archive, destination):
    with tarfile.open(archive, "r:") as tar:
        members = tar.getmembers()
        kinds = {}
        for member in members:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or ".." in path.parts or not path.parts
                    or path.parts[0] not in NAMES or str(path) != member.name.rstrip("/")
                    or member.name.rstrip("/") in kinds
                    or not (member.isdir() or member.isfile() or member.issym())):
                raise ValueError("unsafe archive")
            kinds[member.name.rstrip("/")] = member
        for path, member in kinds.items():
            for parent in PurePosixPath(path).parents:
                if str(parent) != "." and (str(parent) not in kinds or not kinds[str(parent)].isdir()):
                    raise ValueError("unsafe archive parent")
        for name in NAMES:
            if name not in kinds or not kinds[name].isdir():
                raise ValueError("archive scope missing")
            db = kinds.get(name + "/state.db")
            if db is None or not db.isfile():
                raise ValueError("unsafe database")
            for suffix in ("-wal", "-shm", "-journal"):
                sidecar = kinds.get(name + "/state.db" + suffix)
                if sidecar is not None and not sidecar.isfile():
                    raise ValueError("unsafe database sidecar")
        # Outward declarative symlinks are preserved, never followed. No member
        # may have a symlink parent; hardlinks/devices/FIFOs were rejected above.
        tar.extractall(destination, members=members, filter="fully_trusted")


def verify(destination, compare):
    global PHASE
    def walk(source, restored):
        if set(os.listdir(source)) != set(os.listdir(restored)):
            raise ValueError("restore mismatch")
        for entry in list(source.iterdir()):
            left, right = entry, restored / entry.name
            a, b = left.lstat(), right.lstat()
            if stat.S_IFMT(a.st_mode) != stat.S_IFMT(b.st_mode):
                raise ValueError("restore mismatch")
            if stat.S_ISLNK(a.st_mode):
                equal = os.readlink(left) == os.readlink(right)
            elif stat.S_ISDIR(a.st_mode):
                walk(left, right)
                equal = True
            elif stat.S_ISREG(a.st_mode):
                equal = filecmp.cmp(left, right, shallow=False)
            else:
                equal = False
            if not equal:
                raise ValueError("restore mismatch")
    for name in NAMES:
        home = destination / name
        if compare:
            walk(ROOT / name, home)
        # mode=ro applies pending WAL without reading any application rows.
        PHASE = "integrity"
        with contextlib.closing(sqlite3.connect((home / "state.db").as_uri() + "?mode=ro", uri=True)) as db:
            if db.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("database integrity failed")


def receive_archive(compare):
    with tempfile.TemporaryDirectory(prefix="hermes-state-restore-") as tmp:
        destination = Path(tmp) / "restore"
        destination.mkdir(mode=0o700)
        archive = Path(tmp) / ARCHIVE
        with archive.open("wb") as stream:
            shutil.copyfileobj(sys.stdin.buffer, stream)
        extract(archive, destination)
        verify(destination, compare)


def interrupted(signum, frame):
    raise TimeoutError("operation interrupted")


def remote(mode):
    global PHASE
    if mode == "rehearse":
        signal.alarm(LIMIT)
        receive_archive(False)
        return
    PHASE = "supervisor-preflight"
    preflight()
    prior = states()
    if mode == "preflight":
        print("PASS hermes-state-preflight-remote")
        return
    try:
        PHASE = "quiesce"
        for name in TIMERS + HEALTH + WRITERS:
            if prior[name] != "absent":
                unit("stop", name)
        stopped()
        PHASE = "archive"
        send_archive()
        signal.alarm(LIMIT)
        PHASE = "isolated-restore"
        receive_archive(True)
    finally:
        original_phase = PHASE
        PHASE = "recovery"
        signal.alarm(0)
        # Finish recovery even if another catchable signal arrives.
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP, signal.SIGALRM):
            signal.signal(sig, signal.SIG_IGN)
        failures = False
        for name in WRITERS + TIMERS:
            if prior[name] == "active":
                try:
                    unit("start", name)
                except Exception:
                    failures = True
        try:
            recovered = states()
            if any(recovered[name] != prior[name] for name in WRITERS + TIMERS):
                failures = True
        except Exception:
            failures = True
        if failures:
            raise RuntimeError("recovery requires attention")
        PHASE = original_phase


def metadata(restic, snapshot):
    values = json.loads(run(restic + ["snapshots", "--json", snapshot], stdout=subprocess.PIPE).stdout)
    if (len(values) != 1 or values[0].get("id") != snapshot
            or values[0].get("tags") != [TAG] or values[0].get("paths") != ["/" + ARCHIVE]):
        raise ValueError("snapshot scope mismatch")


def local(script, mode, discovery, kepler, interpreter, snapshot=None):
    global PHASE, REMOTE_DIAGNOSTIC
    PHASE = "supervisor-preflight"
    REMOTE_DIAGNOSTIC = None
    if mode not in ("backup", "rehearse", "preflight") or (mode == "rehearse" and snapshot is None):
        raise ValueError("invalid operation")
    if snapshot is not None:
        valid_id(snapshot)  # Before any SSH or service action.
    if not re.fullmatch(r"/nix/store/[0-9a-z]{32}-python3-[0-9][0-9A-Za-z.+_-]*/bin/python3", interpreter):
        raise ValueError("invalid pinned interpreter")
    for address in (discovery, kepler):
        if not re.fullmatch(r"[A-Za-z0-9.:-]+", address):
            raise ValueError("invalid fleet address")
    source = Path(script).read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
    ssh = ["ssh", "-p", "2222", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "erik@" + discovery]
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="hermes-state-backup-") as tmp:
        password = Path(tmp) / "restic-password"
        PHASE = "credential-preflight"
        # Authentication happens before units stop. Never capture/log values.
        with password.open("wb") as out:
            run(ssh + ["sudo -n sh -c 'test -f /run/secrets/vault_restic_password && test ! -L /run/secrets/vault_restic_password && case $(stat -c %a /run/secrets/vault_restic_password) in 400|600) ;; *) exit 1;; esac && cat /run/secrets/vault_restic_password'"], stdout=out)
        if password.stat().st_size == 0:
            raise ValueError("password unavailable")
        os.environ["RESTIC_PASSWORD_FILE"] = str(password)
        for variable in ("RESTIC_PASSWORD", "RESTIC_PASSWORD_COMMAND", "RESTIC_REPOSITORY_FILE"):
            os.environ.pop(variable, None)
        os.environ["RESTIC_REPOSITORY"] = "sftp:erik@" + kepler + ":/bulk/backups/discovery-esp-home"
        os.environ["RESTIC_SFTP_COMMAND"] = "ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=15 erik@" + kepler + " -s sftp"
        # Explicit option uses same authenticated local SSH context as old recipe.
        restic = ["restic", "-o", "sftp.command=" + os.environ["RESTIC_SFTP_COMMAND"]]
        PHASE = "repository-preflight"
        run(restic + ["snapshots", "--no-lock", "--json"], stdout=subprocess.DEVNULL)
        if snapshot:
            PHASE = "snapshot-validation"
            metadata(restic, snapshot)
        command = "sudo -n " + shlex.quote(interpreter) + " -c " + shlex.quote(source) + " --remote " + mode
        PHASE = "remote-unobserved"
        if mode == "preflight":
            result = subprocess.run(ssh + [command], stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, timeout=LIMIT)
            if result.returncode or result.stdout != b"PASS hermes-state-preflight-remote\n":
                # Only module-owned allowlisted fields survive arbitrary SSH output.
                try:
                    value = json.loads(result.stdout) if len(result.stdout) <= 512 else None
                    if (isinstance(value, dict) and set(value) <= {"phase", "class", "returncode"}
                            and value.get("phase") == "supervisor-preflight" and value.get("class") in ERROR_CLASSES | {"OtherError"}
                            and ("returncode" not in value or type(value["returncode"]) is int)):
                        REMOTE_DIAGNOSTIC = value
                except (ValueError, TypeError):
                    pass
                if result.returncode == 0:
                    raise ValueError("invalid preflight response")
                raise subprocess.CalledProcessError(result.returncode, [])
            print("PASS hermes-state-preflight")
            return
        supervisor = subprocess.Popen(ssh + [command], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.DEVNULL)
        try:
            if mode == "backup":
                snapshot = frame_backup(supervisor.stdout, restic, tmp)
                PHASE = "snapshot-validation"
                metadata(restic, snapshot)
            PHASE = "isolated-restore"
            run(restic + ["dump", snapshot, ARCHIVE], stdout=supervisor.stdin)
            supervisor.stdin.close()
            PHASE = "remote-unobserved"  # Remote integrity/recovery not observed here.
            if supervisor.wait(timeout=LIMIT + 30) != 0:
                raise ValueError("restore or recovery failed")
            if supervisor.stdout.read(1):
                raise ValueError("trailing archive frame data")
            print("PASS hermes-state-backup snapshot=" + snapshot if mode == "backup"
                  else "PASS hermes-state-rehearsal snapshot=" + snapshot)
        finally:
            supervisor.stdout.close()
            supervisor.stdin.close()
            # No outer SSH kill: remote EOF/alarm triggers supervised recovery.
            if supervisor.poll() is None:
                supervisor.wait(timeout=LIMIT + 30)


if __name__ == "__main__":
    os.umask(0o077)
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP, signal.SIGALRM):
        signal.signal(sig, interrupted)
    try:
        if sys.argv[1:2] == ["--remote"]:
            remote(sys.argv[2])
        else:
            local(*sys.argv[1:])
    except BaseException as error:
        # No exception text: tools may include private paths or credentials.
        value = REMOTE_DIAGNOSTIC or diagnostic(error)
        if sys.argv[1:3] == ["--remote", "preflight"]:
            print(json.dumps(value, sort_keys=True))
        else:
            print("BLOCKED hermes-state-backup " + json.dumps(value, sort_keys=True), file=sys.stderr)
        sys.exit(1)
PY
