"""Finite, read-only integrity checks with private receipts and durable findings."""
import argparse
import ctypes
from contextlib import ExitStack
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import selectors
import signal
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

spec = importlib.util.spec_from_file_location("integrity_report", Path(__file__).with_name("_host-integrity-report.py"))
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def reporter(cfg):
    return report.Reporter(cfg["state_dir"], cfg["metrics_dir"], cfg["instance"], cfg["check"])


def command(argv, deadline, cfg, on_line=None):
    proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True)
    output, pending = bytearray(), b""
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("job deadline exceeded")
                for key, _ in selector.select(min(remaining, 0.1)):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    excess = len(output) + len(chunk) > cfg["outputMaxBytes"]
                    chunk = chunk[:max(0, cfg["outputMaxBytes"] - len(output))]
                    output.extend(chunk)
                    pending += chunk
                    while b"\n" in pending:
                        line, pending = pending.split(b"\n", 1)
                        if on_line:
                            on_line(line.decode(errors="replace"))
                    if excess:
                        raise ValueError("tool output limit exceeded")
            if pending and on_line:
                on_line(pending.decode(errors="replace"))
        return proc.wait(timeout=max(0.01, deadline - time.monotonic())), output.decode(errors="replace")
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        proc.stdout.close()


def database(directory):
    selected = {}
    for name in ("main", "daily", "bytecode"):
        candidates = []
        for suffix in ("cvd", "cld"):
            path = Path(directory) / f"{name}.{suffix}"
            if not path.exists():
                continue
            with path.open("rb") as stream:
                header = stream.read(512).decode("ascii").strip(" \x00\n").split(":")
            if len(header) != 9 or header[0] != "ClamAV-VDB":
                raise ValueError("invalid database header")
            version, published = int(header[2]), int(header[8])
            if version < 0 or not 0 < published <= time.time():
                raise ValueError("invalid database metadata")
            candidates.append(dict(path=str(path), version=version, published=published))
        if not candidates:
            raise ValueError("incomplete standard database set")
        selected[name] = max(candidates, key=lambda item: (item["version"], item["path"]))
    return dict(selected["daily"], selected=selected)


def open_local(path, directory=-100):
    # Linux openat2 is syscall 437 on both supported fleet architectures.
    if platform.machine() not in ("x86_64", "aarch64"):
        raise RuntimeError("unsupported openat2 architecture")
    class How(ctypes.Structure):
        _fields_ = [("flags", ctypes.c_uint64), ("mode", ctypes.c_uint64), ("resolve", ctypes.c_uint64)]
    how = How(os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK, 0, 4 | (1 if directory != -100 else 0))
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    fd = libc.syscall(437, directory, os.fsencode(path), ctypes.byref(how), ctypes.sizeof(how))
    if fd < 0:
        errno = ctypes.get_errno()
        raise OSError(errno, os.strerror(errno))
    return fd


def stage_scope(cfg, deadline, destination):
    local = {"ext2", "ext3", "ext4", "btrfs", "zfs", "xfs", "tmpfs", "overlay", "vfat"}
    mounts = {line.split()[0]: line.split(" - ", 1)[1].split()[0]
              for line in Path("/proc/self/mountinfo").read_text().splitlines()}
    counts = dict(visited=0, skipped=0, bytes=0, files=0, mapping={})
    def visit(fd, depth, source):
        if time.monotonic() >= deadline:
            raise TimeoutError("scope deadline exceeded")
        counts["visited"] += 1
        if counts["visited"] > cfg["maxFiles"] or depth > cfg["maxRecursion"]:
            counts["skipped"] += 1
            return
        before = os.fstat(fd)
        if stat.S_ISDIR(before.st_mode):
            with os.scandir(fd) as entries:
                for entry in entries:
                    if time.monotonic() >= deadline:
                        raise TimeoutError("scope deadline exceeded")
                    if counts["visited"] >= cfg["maxFiles"]:
                        counts["skipped"] += 1
                        break
                    try:
                        child = open_local(entry.name, fd)
                    except OSError:
                        counts["visited"] += 1
                        counts["skipped"] += 1
                        continue
                    try:
                        visit(child, depth + 1, str(Path(source) / entry.name))
                    finally:
                        os.close(child)
        elif not stat.S_ISREG(before.st_mode) or before.st_size > cfg["maxFileBytes"]:
            counts["skipped"] += 1
        elif before.st_size > cfg["maxTotalBytes"] - counts["bytes"]:
            counts["skipped"] += 1
        else:
            target = destination / str(counts["files"])
            with target.open("xb") as output:
                while True:
                    if time.monotonic() >= deadline:
                        raise TimeoutError("copy deadline exceeded")
                    chunk = os.read(fd, min(65536, before.st_size - output.tell() + 1))
                    if not chunk:
                        break
                    if output.tell() + len(chunk) > before.st_size:
                        break
                    output.write(chunk)
            after = os.fstat(fd)
            if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns) or target.stat().st_size != before.st_size:
                target.unlink()
                counts["skipped"] += 1
            else:
                counts["mapping"][str(counts["files"])] = source
                counts["bytes"] += before.st_size
                counts["files"] += 1
    for raw in cfg["paths"]:
        try:
            fd = open_local(raw)
        except OSError:
            counts["skipped"] += 1
            continue
        try:
            mount = next(line.split()[1] for line in Path(f"/proc/self/fdinfo/{fd}").read_text().splitlines() if line.startswith("mnt_id:"))
            if mounts.get(mount) not in local:
                counts["skipped"] += 1
            else:
                visit(fd, 0, raw)
        except OSError:
            counts["skipped"] += 1
        finally:
            os.close(fd)
    return counts


def receipt(cfg, started, result, counts, version, db, details):
    directory = Path(cfg["state_dir"]) / "receipts"
    directory.mkdir(mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    record = dict(schemaRevision=1, instance=cfg["instance"], check=cfg["check"],
                  scopeId=cfg["scopeId"], sourceRevision=cfg["sourceRevision"],
                  started=started, ended=time.time(), state=result, counts=counts,
                  toolVersion=version, commandPolicy=cfg, database=db,
                  exclusions=["symlinks", "nested mounts", "nonlocal filesystems", "nonregular files", "configured limits"],
                  priorFindingResolved=False, details=details)
    report.atomic_write(directory / f'{cfg["check"]}-{uuid.uuid4().hex}.json', json.dumps(record) + "\n", 0o600)
    files = sorted(directory.glob(f'{cfg["check"]}-*.json'), key=lambda path: path.stat().st_mtime, reverse=True)
    for index, path in enumerate(files):
        if index >= cfg["maxReceipts"] or path.stat().st_mtime < time.time() - cfg["retentionDays"] * 86400:
            path.unlink()


def service_failure(cfg, result):
    if result == "success":
        return
    r = reporter(cfg)
    previous = r.update("publish")
    if previous["state"] != 1:
        r.update("begin")
    counts = dict(findings=previous["findings"], skipped=previous["skipped"], errors=previous["errors"] + 1)
    r.update("failed", finding_source="retained", **counts)
    receipt(cfg, time.time(), "failed", counts, "unavailable", None, [result])


def run(cfg):
    r = reporter(cfg)
    started = time.time()
    deadline = time.monotonic() + cfg["timeoutSeconds"]
    counts = dict(findings=0, skipped=0, errors=0)
    db, version, details = None, "unknown", []
    lock_fd = os.open(Path(cfg["state_dir"]) / f'{cfg["check"]}.run.lock', os.O_CREAT | os.O_RDWR, 0o600)
    with ExitStack() as resources:
        lock = resources.enter_context(os.fdopen(lock_fd, "w"))
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if cfg.get("coordinationLock"):
                fd = os.open(cfg["coordinationLock"], os.O_CREAT | os.O_RDWR, 0o600)
                coordination = resources.enter_context(os.fdopen(fd, "w"))
                fcntl.flock(coordination, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if cfg["check"] in ("store", "av"):
                fd = os.open(Path(cfg["state_dir"]) / "heavy.run.lock", os.O_CREAT | os.O_RDWR, 0o600)
                heavy_lock = resources.enter_context(os.fdopen(fd, "w"))
                fcntl.flock(heavy_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if cfg["check"] in ("signatures", "av"):
                fd = os.open(Path(cfg["state_dir"]) / "database.run.lock", os.O_CREAT | os.O_RDWR, 0o600)
                db_lock = resources.enter_context(os.fdopen(fd, "w"))
                mode = fcntl.LOCK_EX if cfg["check"] == "signatures" else fcntl.LOCK_SH
                fcntl.flock(db_lock, mode | fcntl.LOCK_NB)
        except BlockingIOError:
            service_failure(cfg, "lock-conflict")
            return
        r.update("begin", now=started)
        try:
            code, version = command([cfg["command"][0], "--version"], deadline, cfg)
            if code:
                raise ValueError("tool version unavailable")
            if cfg["check"] == "signatures":
                code, output = command(cfg["command"], deadline, cfg)
                details.append(output)
                db = database(cfg["databaseDirectory"])
                counts["errors"] = int(code != 0)
            elif cfg["check"] == "store":
                code, output = command(cfg["command"], deadline, cfg)
                details.append(output)
                counts["findings"] = int(code >= 0 and bool(code & 3))
                counts["errors"] = int(code < 0 or code > 7 or bool(code & 4))
            else:
                db = database(cfg["databaseDirectory"])
                database_args = [f'--database={entry["path"]}' for entry in db["selected"].values()]
                Path(cfg["work_dir"]).mkdir(mode=0o700, parents=True, exist_ok=True)
                for abandoned in Path(cfg["work_dir"]).glob("batch-*"):
                    if abandoned.is_symlink():
                        abandoned.unlink()
                    else:
                        shutil.rmtree(abandoned)
                with tempfile.TemporaryDirectory(prefix="batch-", dir=cfg["work_dir"]) as temporary:
                    staging = Path(temporary)
                    copied = stage_scope(cfg, deadline, staging)
                    counts["skipped"] += copied["skipped"]
                    details.append({"stagedSources": copied["mapping"]})
                    recognized = 0
                    def observed(line):
                        nonlocal recognized
                        match = re.fullmatch(r".+: (.+) FOUND", line)
                        if match:
                            recognized += 1
                            details.append({"observedFinding": line})
                            key = "skipped" if match[1].startswith(("Heuristics.Limits.", "Heuristics.Encrypted.")) else "findings"
                            counts[key] += 1
                            r.update("progress", **counts)
                    if copied["files"]:
                        listing = staging / "files.txt"
                        listing.write_text("".join(str(staging / str(i)) + "\n" for i in range(copied["files"])))
                        code, output = command(cfg["command"] + database_args + [f"--file-list={listing}"], deadline, cfg, observed)
                        details.append(output)
                        counts["errors"] += int(code not in (0, 1))
                        if code == 1 and not recognized:
                            counts["errors"] += 1
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
            counts["errors"] += 1
            details.append(type(error).__name__)
        result = "failed" if counts["errors"] else "partial" if counts["skipped"] else "complete"
        extra = {"database_seconds": db["published"] if db else 0} if cfg["check"] == "signatures" else {}
        # A competing attempt invalidates this coverage; never overwrite its failure with success.
        current = r.update("publish")
        if current["state"] != 1:
            counts["errors"] += 1
            result = "failed"
            r.update("begin")
        try:
            receipt(cfg, started, result, counts, version, db, details)
        except OSError:
            counts["errors"] += 1
            result = "failed"
        r.update(result, **counts, **extra)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--service-result")
    args = parser.parse_args()
    cfg = json.loads(Path(args.config).read_text())
    if args.service_result is not None:
        service_failure(cfg, args.service_result)
    else:
        run(cfg)
