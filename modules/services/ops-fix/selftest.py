#!/usr/bin/env python3
"""Stdlib self-check for the ops-fix runner policy (no docker, no root)."""
from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
RUNNER = HERE / "ops-fix-runner.py"


def load():
    spec = importlib.util.spec_from_file_location("ops_fix_runner", RUNNER)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ops_fix_runner"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


ALLOW = {"containers": {"prowlarr": "discovery"}}


def test_validate():
    mod = load()
    assert mod.validate("status", "anything", ALLOW) is None
    assert mod.validate("restart_container", "prowlarr", ALLOW) is None
    assert mod.validate("restart_container", "hermes-argus", ALLOW)
    assert mod.validate("restart_unit", "prowlarr", ALLOW)
    assert mod.validate("shell", "prowlarr", ALLOW)


def test_rate_limit():
    with tempfile.TemporaryDirectory() as tmp:
        mod = load()
        mod.STATE_DIR = pathlib.Path(tmp)
        assert mod.rate_limited("prowlarr", now=1000, state={"last_action": {}}) is False
        state = {"last_action": {"prowlarr": 900}}
        assert mod.rate_limited("prowlarr", now=1000, state=state) is True
        assert mod.rate_limited("prowlarr", now=900 + mod.MIN_INTERVAL + 1, state=state) is False


def test_handle_rejects_without_executing():
    mod = load()
    bad = mod.handle({"action": "restart_container", "target": "hermes-argus"}, ALLOW)
    assert bad["ok"] is False and "not allowlisted" in bad["error"]
    bad = mod.handle({"action": "shell", "target": "prowlarr"}, ALLOW)
    assert bad["ok"] is False and "not allowed" in bad["error"]
    bad = mod.handle({}, ALLOW)
    assert bad["ok"] is False


def test_handle_restart_is_gated_and_audited():
    with tempfile.TemporaryDirectory() as tmp:
        mod = load()
        mod.STATE_DIR = pathlib.Path(tmp)
        mod.restart_container = lambda target: "running healthy"
        out = mod.handle({"action": "restart_container", "target": "prowlarr"}, ALLOW)
        assert out["ok"] is True, out
        assert out["detail"] == "running healthy"
        audit = (pathlib.Path(tmp) / "audit.jsonl").read_text()
        assert "prowlarr" in audit
        again = mod.handle({"action": "restart_container", "target": "prowlarr"}, ALLOW)
        assert again["ok"] is False and again["error"] == "rate limited", again


def test_allowlist_shape():
    mod = load()
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "a.json"
        path.write_text('{"containers": {"prowlarr": "discovery"}}')
        assert mod.load_allowlist(str(path))["containers"]["prowlarr"] == "discovery"
        path.write_text('{"containers": []}')
        assert mod.load_allowlist(str(path))["containers"] == {}
        path.write_text('{"containers": "nope"}')
        try:
            mod.load_allowlist(str(path))
        except ValueError:
            pass
        else:
            raise AssertionError("bad allowlist accepted")


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS ops-fix-selftest")


if __name__ == "__main__":
    main()
