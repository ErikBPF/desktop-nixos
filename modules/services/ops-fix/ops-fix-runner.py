#!/usr/bin/env python3
"""Minimal host-side action runner for Argus (Cleytin).

Listens on a Unix socket, accepts one JSON request per connection, and executes
only the actions and targets in the allowlist file. No shell, no free-form
commands, no network. Root-only socket, rate-limited per target, append-only
audit log.
"""
from __future__ import annotations

import json
import os
import pathlib
import socket
import subprocess
import sys
import time

SOCKET = os.environ.get("OPS_FIX_SOCKET", "/run/ops-fix/ops.sock")
ALLOWLIST = os.environ.get("OPS_FIX_ALLOWLIST", "/etc/ops-fix/allowlist.json")
STATE_DIR = pathlib.Path(os.environ.get("OPS_FIX_STATE", "/var/lib/ops-fix"))
MIN_INTERVAL = int(os.environ.get("OPS_FIX_MIN_INTERVAL", "1800"))
VERIFY_SECONDS = int(os.environ.get("OPS_FIX_VERIFY_SECONDS", "60"))


def load_allowlist(path: str = ALLOWLIST) -> dict:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    containers = data.get("containers") or {}
    if not isinstance(containers, dict):
        raise ValueError("allowlist.containers must be an object")
    return {"containers": {str(k): str(v) for k, v in containers.items()}}


def validate(action: str, target: str, allowlist: dict) -> str | None:
    if action == "status":
        return None
    if action != "restart_container":
        return f"action {action!r} is not allowed"
    if target not in allowlist["containers"]:
        return f"target {target!r} is not allowlisted"
    return None


def _state_path() -> pathlib.Path:
    return STATE_DIR / "state.json"


def read_state() -> dict:
    try:
        return json.loads(_state_path().read_text(encoding="utf-8"))
    except Exception:
        return {"last_action": {}}


def rate_limited(target: str, now: float | None = None, state: dict | None = None) -> bool:
    now = time.time() if now is None else now
    state = read_state() if state is None else state
    entry = state.get("last_action", {}).get(target)
    if entry is None:
        return False
    return (now - float(entry)) < MIN_INTERVAL


def record_action(target: str, detail: str, now: float | None = None) -> None:
    now = time.time() if now is None else now
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state = read_state()
    state.setdefault("last_action", {})[target] = now
    tmp = _state_path().with_suffix(".tmp")
    tmp.write_text(json.dumps(state), encoding="utf-8")
    os.replace(tmp, _state_path())
    with (STATE_DIR / "audit.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"ts": now, "target": target, "detail": detail}) + "\n")


def _run(argv: list[str], timeout: int = 30) -> str:
    proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout or "command failed").strip()[:400])
    return proc.stdout.strip()


def container_status(target: str) -> str:
    return _run([
        "docker", "inspect", "-f",
        "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}", target,
    ])


def restart_container(target: str) -> str:
    _run(["docker", "restart", target], timeout=90)
    deadline = time.time() + VERIFY_SECONDS
    status = ""
    while time.time() < deadline:
        try:
            status = container_status(target)
        except Exception:
            status = "inspect-failed"
        if status.startswith("running") and ("healthy" in status or status.strip() == "running"):
            return status
        time.sleep(2)
    return status or "unknown"


def handle(request: dict, allowlist: dict) -> dict:
    action = str(request.get("action") or "")
    target = str(request.get("target") or "")
    error = validate(action, target, allowlist)
    if error:
        return {"ok": False, "error": error, "action": action, "target": target}
    try:
        if action == "status":
            return {"ok": True, "action": action, "target": target,
                    "detail": container_status(target)}
        if target not in allowlist["containers"]:
            return {"ok": False, "error": "target not allowlisted", "action": action, "target": target}
        if rate_limited(target):
            return {"ok": False, "error": "rate limited", "action": action, "target": target}
        detail = restart_container(target)
        record_action(target, detail)
        return {"ok": True, "action": action, "target": target, "detail": detail}
    except Exception as exc:  # never leak a traceback to the caller
        return {"ok": False, "error": str(exc)[:400], "action": action, "target": target}


def serve(socket_path: str = SOCKET) -> None:
    allowlist = load_allowlist()
    path = pathlib.Path(socket_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(path))
    os.chmod(path, 0o600)
    server.listen(4)
    while True:
        conn, _ = server.accept()
        with conn:
            try:
                conn.settimeout(10)
                raw = b""
                while b"\n" not in raw and len(raw) < 4096:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    raw += chunk
                request = json.loads(raw.split(b"\n", 1)[0] or b"{}")
                response = handle(request if isinstance(request, dict) else {}, allowlist)
            except Exception as exc:
                response = {"ok": False, "error": f"bad request: {exc}"[:200]}
            conn.sendall((json.dumps(response) + "\n").encode("utf-8"))


if __name__ == "__main__":
    try:
        serve(sys.argv[1] if len(sys.argv) > 1 else SOCKET)
    except KeyboardInterrupt:
        pass
