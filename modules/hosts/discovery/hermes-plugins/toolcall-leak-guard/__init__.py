"""toolcall-leak-guard — strip fabricated tool-call payloads from outbound text.

Weak open models given NO tools sometimes answer with a tool-call payload as
ordinary text (``<invoke name="bash">…</invoke>``, ``<tool_call>…``, Harmony
``to=functions.x``, a ```tool_call fence). Argus runs with zero platform
toolsets, so such a call is invalid — yet Hermes would post the raw block to
Discord verbatim, which is exactly the 2026-09 Cleytin triage regression.

Registers a ``transform_llm_output`` hook (fires once per turn, after the
tool loop, before delivery; a non-empty returned string replaces the text):

- leaked block(s) removed, real prose kept;
- if nothing but leaked blocks remained, return ``NO_REPLY`` so the gateway's
  intentional-silence filter suppresses the send entirely;
- no leak detected → ``None`` (leave the response unchanged).

Fail-open: any error leaves the response unchanged.
"""

from __future__ import annotations

import logging
import re
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from hermes_cli.plugins import PluginContext

logger = logging.getLogger("toolcall-leak-guard")

# Fast sniff — cheap test that ANY fabricated-tool-call marker is present.
_LEAK_SNIFF = re.compile(
    r"<invoke\b|<tool_call\b|<function_calls?\b|to=functions\.|"
    r"\binvoke\s+name\s*=|```[ \t]*(?:tool_calls?|function_calls?|invoke)\b",
    re.IGNORECASE,
)

# Balanced blocks: remove opener..closer wholesale (DOTALL, non-greedy).
_BALANCED = (
    re.compile(r"<invoke\b[^>]*>.*?</invoke>", re.IGNORECASE | re.DOTALL),
    re.compile(r"<tool_call\b[^>]*>.*?</tool_call>", re.IGNORECASE | re.DOTALL),
    re.compile(r"<function_call\b[^>]*>.*?</function_call>", re.IGNORECASE | re.DOTALL),
    re.compile(r"<function_calls\b[^>]*>.*?</function_calls>", re.IGNORECASE | re.DOTALL),
    re.compile(r"<\|tool_call\|>.*?<\|/tool_call\|>", re.IGNORECASE | re.DOTALL),
    re.compile(
        r"```[ \t]*(?:tool_calls?|function_calls?|invoke)\b[^\n]*\n.*?```",
        re.IGNORECASE | re.DOTALL,
    ),
)

# Truncated dumps: opener with no closer, or a bare Harmony call line — drop to
# end of text.
_TAIL_JUNK = (
    re.compile(r"<invoke\b[^>]*>.*$", re.IGNORECASE | re.DOTALL),
    re.compile(r"<tool_call\b[^>]*>.*$", re.IGNORECASE | re.DOTALL),
    re.compile(r"<function_calls?\b[^>]*>.*$", re.IGNORECASE | re.DOTALL),
    re.compile(r"(?im)^[ \t]*to=functions\.[A-Za-z0-9_.]+[ \t]*$"),
)

NO_REPLY = "NO_REPLY"


def clean_response(text: str) -> Optional[str]:
    """Return the sanitized text, ``NO_REPLY``, or ``None`` to leave unchanged."""
    if not text or not _LEAK_SNIFF.search(text):
        return None

    cleaned = text
    for pattern in _BALANCED:
        cleaned = pattern.sub("", cleaned)
    for pattern in _TAIL_JUNK:
        cleaned = pattern.sub("", cleaned)
    cleaned = cleaned.strip()

    # Anything that still trips the sniffer is leftover block innards, not
    # usable prose — suppress rather than post shell fragments as a "verdict".
    if not cleaned or _LEAK_SNIFF.search(cleaned):
        return NO_REPLY
    return cleaned


def _transform_llm_output(*, response_text: str = "", **_kw) -> Optional[str]:
    try:
        result = clean_response(response_text)
    except Exception as exc:  # fail-open: never break a turn
        logger.warning("[toolcall-leak-guard] clean failed: %s", exc)
        return None
    if result is NO_REPLY:
        logger.info("[toolcall-leak-guard] suppressed leak-only response")
    elif result is not None:
        logger.info(
            "[toolcall-leak-guard] stripped leaked tool-call block (%d -> %d chars)",
            len(response_text), len(result),
        )
    return result


def register(ctx: "PluginContext") -> None:
    ctx.register_hook("transform_llm_output", _transform_llm_output)
