#!/usr/bin/env python3
"""Operator-only materialization of the reviewed private Servarr transport."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile


def materialize(directory, content, expected_sha256):
    directory = Path(directory)
    if len(content) > 131072 or hashlib.sha256(content).hexdigest() != expected_sha256:
        raise ValueError("Downloaded artifact differs from reviewed SHA256")
    directory.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    parent = directory.parent.lstat()
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.geteuid() or parent.st_mode & 0o022:
        raise ValueError("Release parent is not privately controlled")
    target = directory / "wazuh-backup.py"
    if directory.exists() or directory.is_symlink():
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o222:
            raise ValueError("Existing release is not immutable")
        fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o222:
                raise ValueError("Existing artifact is not immutable")
            installed = source.read(131073)
        if hashlib.sha256(installed).hexdigest() != expected_sha256:
            raise ValueError("Refusing to overwrite a different existing release")
        return
    temporary = Path(tempfile.mkdtemp(prefix=".install-", dir=directory.parent))
    try:
        target = temporary / "wazuh-backup.py"
        with target.open("xb") as output:
            output.write(content)
            output.flush()
            os.fchmod(output.fileno(), 0o500)
            os.fsync(output.fileno())
        # Verify bytes after installation, independently of the incoming digest.
        if hashlib.sha256(target.read_bytes()).hexdigest() != expected_sha256:
            raise ValueError("Installed artifact verification failed")
        temporary.chmod(0o500)
        fd = os.open(temporary, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        os.rename(temporary, directory)
        fd = os.open(directory.parent, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        if temporary.exists():
            temporary.chmod(0o700)
            shutil.rmtree(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--receive", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.revision) or not re.fullmatch(r"[0-9a-f]{64}", args.sha256):
        raise ValueError("Expected exact published commit and file digest")
    os.umask(0o077)
    if args.receive:
        if os.geteuid() != 0:
            raise PermissionError("Materialization requires the operator's root deployment context")
        directory = Path("/var/lib/wazuh-manager-capture/transport") / args.revision
        materialize(directory, sys.stdin.buffer.read(131073), args.sha256)
        print("Verified private Wazuh transport release " + args.revision)
        return
    root = Path(__file__).resolve().parents[1]
    host = json.loads((root / "fleet.json").read_text())["hosts"]["kepler"]["ip"]
    endpoint = "repos/ErikBPF/servarr/contents/machines/kepler/scripts/wazuh-backup.py?ref=" + args.revision
    response = subprocess.run(["gh", "api", endpoint], capture_output=True, check=True, timeout=60)
    content = base64.b64decode("".join(json.loads(response.stdout)["content"].split()), validate=True)
    if len(content) > 131072 or hashlib.sha256(content).hexdigest() != args.sha256:
        raise ValueError("Published artifact does not match reviewed pin")
    # Only public installer code is in argv. Private source travels through SSH stdin.
    command = shlex.join(["sudo", "-n", "/run/current-system/sw/bin/python3", "-I", "-c", Path(__file__).read_text(),
                          "--receive", "--revision", args.revision, "--sha256", args.sha256])
    subprocess.run(["ssh", "-p", "2222", "-o", "BatchMode=yes", "erik@" + host, command],
                   input=content, check=True, timeout=90)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        raise SystemExit(f"Wazuh transport materialization failed ({type(error).__name__})") from None
