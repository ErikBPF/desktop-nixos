import hashlib
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    "installer", Path(__file__).parents[2] / "scripts/install-wazuh-transport.py"
)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def test_installed_artifact_is_verified_and_nonwritable(tmp_path):
    directory = tmp_path / ("a" * 40)
    content = b"VALUE = 42\n"
    digest = hashlib.sha256(content).hexdigest()
    installer.materialize(directory, content, digest)
    target = directory / "wazuh-backup.py"
    assert target.exists(), "exact reviewed artifact was not installed"
    assert target.read_bytes() == content
    assert target.stat().st_mode & 0o777 == 0o500
    assert directory.stat().st_mode & 0o777 == 0o500
    installer.materialize(directory, content, digest)
    directory.chmod(0o700)


def test_wrong_hash_cannot_create_a_release(tmp_path):
    directory = tmp_path / ("a" * 40)
    with pytest.raises(ValueError):
        installer.materialize(directory, b"changed", "0" * 64)
    assert not directory.exists()


def test_existing_release_never_overwritten(tmp_path):
    directory = tmp_path / ("a" * 40)
    directory.mkdir()
    target = directory / "wazuh-backup.py"
    target.write_bytes(b"old")
    digest = hashlib.sha256(b"new").hexdigest()
    with pytest.raises(ValueError):
        installer.materialize(directory, b"new", digest)
    assert target.read_bytes() == b"old"


def test_operator_uses_declared_remote_interpreter_and_private_stdin(monkeypatch):
    import base64
    import json
    import shlex
    import subprocess
    import sys
    content = b"PRIVATE_FIXTURE = 42\n"
    digest = hashlib.sha256(content).hexdigest()
    calls = []
    def run(command, **kwargs):
        calls.append((command, kwargs))
        if command[0] == "gh":
            return subprocess.CompletedProcess(command, 0, json.dumps({"content": base64.b64encode(content).decode()}).encode())
        return subprocess.CompletedProcess(command, 0)
    monkeypatch.setattr(subprocess, "run", run)
    monkeypatch.setattr(sys, "argv", ["installer", "--revision", "a" * 40, "--sha256", digest])
    installer.main()
    remote, arguments = calls[1]
    assert shlex.split(remote[-1])[2] == "/run/current-system/sw/bin/python3"
    assert shlex.split(remote[-1])[3] == "-I", "root interpreter must ignore user CWD and Python environment"
    assert arguments["input"] == content
    assert content.decode() not in " ".join(remote)
