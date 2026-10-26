#!/usr/bin/env python3
"""Stdlib self-check for the ops-fix tool plugin (no host runner needed)."""
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import socket
import sys
import tempfile
import threading

HERE = pathlib.Path(__file__).resolve().parent
PLUGIN = HERE / "__init__.py"


def load():
    spec = importlib.util.spec_from_file_location("ops_fix", PLUGIN)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ops_fix"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


class FakeRunner:
    def __init__(self, path: str, response: dict):
        self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.srv.bind(path)
        self.srv.listen(1)
        self.response = response
        self.seen: list[dict] = []
        self.thread = threading.Thread(target=self._run, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.thread.join(timeout=2)
        self.srv.close()

    def _run(self):
        conn, _ = self.srv.accept()
        with conn:
            raw = b""
            while b"\n" not in raw:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                raw += chunk
            self.seen.append(json.loads(raw.split(b"\n", 1)[0]))
            conn.sendall((json.dumps(self.response) + "\n").encode())


def test_status_roundtrip_and_schema():
    mod = load()
    with tempfile.TemporaryDirectory() as tmp:
        path = str(pathlib.Path(tmp) / "ops.sock")
        os.environ["OPS_FIX_SOCKET"] = path
        with FakeRunner(path, {"ok": True, "detail": "running healthy"}) as runner:
            out = json.loads(mod.handler({"action": "status", "target": "prowlarr"}))
        assert out["ok"] is True and out["detail"] == "running healthy", out
        assert runner.seen == [{"action": "status", "target": "prowlarr"}], runner.seen
        os.environ.pop("OPS_FIX_SOCKET", None)
    assert mod.SCHEMA["properties"]["action"]["enum"] == ["status", "restart_container"]
    assert mod.SCHEMA["additionalProperties"] is False


def test_local_rejections():
    mod = load()
    for args in (
        {"action": "shell", "target": "prowlarr"},
        {"action": "restart_container", "target": ""},
        {"action": "restart_container", "target": "x" * 65},
        {},
    ):
        out = json.loads(mod.handler(args))
        assert out["ok"] is False, (args, out)


def test_missing_runner_is_a_tool_error():
    mod = load()
    os.environ["OPS_FIX_SOCKET"] = "/nonexistent/ops.sock"
    try:
        out = json.loads(mod.handler({"action": "status", "target": "prowlarr"}))
    finally:
        os.environ.pop("OPS_FIX_SOCKET", None)
    assert out["ok"] is False and "runner unavailable" in out["error"], out


def test_off_mode_and_registration():
    mod = load()
    os.environ["OPS_FIX_MODE"] = "off"
    try:
        out = json.loads(mod.handler({"action": "status", "target": "prowlarr"}))
        assert out["ok"] is False and "disabled" in out["error"], out
    finally:
        os.environ["OPS_FIX_MODE"] = "execute"

    captured = {}

    class Ctx:
        def register_tool(self, **kwargs):
            captured.update(kwargs)

    mod.register(Ctx())
    assert captured["name"] == "ops_fix"
    assert captured["toolset"] == "ops_fix"
    assert captured["handler"] is mod.handler
    assert "allowlist" in captured["description"].lower()


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
    print("PASS ops-fix-tool-selftest")


if __name__ == "__main__":
    main()
