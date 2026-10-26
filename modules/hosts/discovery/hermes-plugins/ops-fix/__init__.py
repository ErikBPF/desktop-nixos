"""Narrow host-action tool for Argus: status and allowlisted container restart.

The tool only speaks the ops-fix Unix-socket protocol; the runner owns the
allowlist, rate limit, execution and audit. The model cannot name a command,
a shell, or a host, and cannot widen its own capability from an alert payload.
"""
from __future__ import annotations

import json
import logging
import os
import socket
from typing import Any

logger = logging.getLogger(__name__)

SOCKET_ENV = "OPS_FIX_SOCKET"
MODE_ENV = "OPS_FIX_MODE"
DEFAULT_SOCKET = "/run/ops-fix/ops.sock"
ACTIONS = ("status", "restart_container")

SCHEMA = {
    "type": "object",
    "properties": {
        "action": {
            "type": "string",
            "enum": list(ACTIONS),
            "description": "status is read-only; restart_container restarts one allowlisted container.",
        },
        "target": {
            "type": "string",
            "description": "Container name exactly as allowlisted by the host runner.",
        },
    },
    "required": ["action", "target"],
    "additionalProperties": False,
}

DESCRIPTION = (
    "Read or restart one allowlisted homelab container through the host runner. "
    "Use status freely. Use restart_container only when the alert is a repeat and "
    "the payload names the same target; the runner rejects anything not allowlisted "
    "and rate-limits repeats. Never invent a target."
)


def _socket_path() -> str:
    return os.environ.get(SOCKET_ENV) or DEFAULT_SOCKET


def _mode() -> str:
    return (os.environ.get(MODE_ENV) or "execute").strip().lower()


def request(payload: dict[str, Any], timeout: float = 90.0) -> dict[str, Any]:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(timeout)
        client.connect(_socket_path())
        client.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        raw = b""
        while b"\n" not in raw:
            chunk = client.recv(4096)
            if not chunk:
                break
            raw += chunk
    line = raw.split(b"\n", 1)[0]
    if not line:
        raise RuntimeError("runner closed the connection without a response")
    response = json.loads(line)
    if not isinstance(response, dict):
        raise ValueError("runner returned a non-object response")
    return response


def handler(args: dict[str, Any], **_kw: Any) -> str:
    if _mode() == "off":
        return json.dumps({"ok": False, "error": "ops-fix is disabled"})
    action = str((args or {}).get("action") or "")
    target = str((args or {}).get("target") or "")
    if action not in ACTIONS:
        return json.dumps({"ok": False, "error": f"unsupported action {action!r}"})
    if not target or len(target) > 64:
        return json.dumps({"ok": False, "error": "a single allowlisted target is required"})
    try:
        return json.dumps(request({"action": action, "target": target}))
    except Exception as exc:  # tool errors are reported, never raised into the turn
        logger.warning("[ops-fix] runner call failed: %s", exc)
        return json.dumps({"ok": False, "error": f"runner unavailable: {exc}"[:300]})


def register(ctx: Any) -> None:
    ctx.register_tool(
        name="ops_fix",
        toolset="ops_fix",
        schema=SCHEMA,
        handler=handler,
        description=DESCRIPTION,
        emoji="\U0001F6E0",
    )
