"""rtk-rewrite — compress terminal output by rewriting commands through rtk.

Registers a ``pre_tool_call`` hook that rewrites the terminal tool's
``command`` to its ``rtk <cmd>`` form via ``rtk rewrite``. The hook receives
the live ``args`` dict by reference (see
``hermes_cli.plugins.get_pre_tool_call_block_message`` →
``invoke_hook("pre_tool_call", args=args, ...)``), so mutating
``args["command"]`` in place propagates to execution — no return value needed.

``rtk rewrite`` is the policy engine: it rewrites read-heavy commands
(git/ls/grep/find/docker/kubectl/cat/log/json/…) and leaves mutating or
unknown commands (rm, echo, …) untouched, emitting nothing. Fail-open: any
error, timeout, or missing rtk leaves the command unchanged.
"""

from __future__ import annotations

import logging
import shutil
import subprocess
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from hermes_cli.plugins import PluginContext

logger = logging.getLogger("rtk-rewrite")
_RTK = "rtk"
_TIMEOUT = 2.0


def _rewrite(command: str) -> Optional[str]:
    """Return the rtk-rewritten command, or None to leave it unchanged."""
    if not shutil.which(_RTK):
        return None
    try:
        proc = subprocess.run(
            [_RTK, "rewrite", command],
            capture_output=True,
            text=True,
            timeout=_TIMEOUT,
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    out = (proc.stdout or "").strip()
    # rtk prints the rewritten command on stdout, or nothing when it declines
    # (mutating/unknown commands). Only accept a real, changed rewrite.
    if out and out != command.strip():
        return out
    return None


def register(ctx: "PluginContext") -> None:
    def pre_tool_call(*, tool_name: str = "", args: Optional[dict] = None, **_kw):
        # Only the terminal tool carries a shell `command`; execute_code uses
        # `code` (python) and is correctly skipped.
        if not isinstance(args, dict):
            return None
        command = args.get("command")
        if not isinstance(command, str) or not command.strip():
            return None
        if command.lstrip().startswith("rtk "):  # already wrapped
            return None
        rewritten = _rewrite(command)
        if rewritten:
            args["command"] = rewritten  # in-place → propagates to execution
            logger.info("[rtk-rewrite] %r -> %r", command, rewritten)
        # Observer-only: never block.
        return None

    ctx.register_hook("pre_tool_call", pre_tool_call)
