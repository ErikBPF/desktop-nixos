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
import ast
import json
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from hermes_cli.plugins import PluginContext

logger = logging.getLogger("toolcall-leak-guard")

# Fast sniff — cheap test that ANY fabricated-tool-call marker is present.
_LEAK_SNIFF = re.compile(
    r"<invoke\b|<tool_call\b|<function_calls?\b|to=functions\.|"
    r"\binvoke\s+name\s*=|```[ \t]*(?:tool_calls?|function_calls?|invoke)\b|"
    r"[\"'](?:tool_calls?|function_calls?)[\"']\s*:",
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

# Closed evidence only; an unfinished fence must not expose inner quotations.
_FENCE_START = re.compile(r"(?m)^ {0,3}(`{3,}|~{3,})[^\n]*\n")
_BLOCKQUOTE = re.compile(r"(?m)^ {0,3}>[^\n]*")


_XML_TAG = re.compile(r"<(/?)(invoke|tool_call|function_calls?)\b", re.IGNORECASE)
_XML_TOKEN = re.compile(r"<!--|<!\[CDATA\[|<\?|<", re.IGNORECASE)
_CALL_KEY = re.compile(r"^(?:tool_calls?|function_calls?)$", re.IGNORECASE)
_TRUNCATED_CALL_KEY = re.compile(r"[\"'](?:tool_calls?|function_calls?)[\"']\s*:", re.IGNORECASE)


def _tool_envelope(text: str) -> bool:
    """Syntax keys identify tool envelopes; literal strings and Markdown do not."""
    try:
        value = json.loads(text)
    except (ValueError, RecursionError):
        try:
            value = ast.literal_eval(text)
        except (ValueError, SyntaxError, RecursionError):
            # Truncated data still fails closed, but a backtick-led Markdown
            # label is not data. Follow only list/object opening punctuation.
            prefix = text.lstrip(" \t\r\n[")
            return bool(re.match(r"\{\s*[\"']", prefix) and _TRUNCATED_CALL_KEY.search(text))
    pending = [value]
    while pending:
        value = pending.pop()
        if isinstance(value, dict):
            if any(isinstance(key, str) and _CALL_KEY.fullmatch(key) for key in value):
                return True
            pending.extend(value.values())
        elif isinstance(value, (list, tuple)):
            pending.extend(value)
    return False


def _escaped(text: str, i: int) -> bool:
    start = i
    while start and text[start - 1] == "\\":
        start -= 1
    return (i - start) % 2 == 1


def _string_end(text: str, start: int) -> int:
    i = start + 1
    while i < len(text):
        if text[i] == "\\":
            i += 2
        elif text[i] == text[start]:
            return i + 1
        else:
            i += 1
    return len(text)


def _tag_end(text: str, start: int) -> int:
    """XML attribute quotes close literally; backslashes never escape them."""
    i = start
    while i < len(text):
        if text[i] in "\"'":
            end = text.find(text[i], i + 1)
            if end == -1:
                return len(text)
            i = end + 1
        elif text[i] == ">":
            return i + 1
        else:
            i += 1
    return len(text)


def _object_end(text: str, start: int) -> int:
    stack = []
    i = start
    while i < len(text):
        char = text[i]
        if char in "\"'":
            i = _string_end(text, i)
            continue
        if char in "{[":
            stack.append(char)
        elif char in "}]":
            if not stack or stack.pop() != {"}": "{", "]": "["}[char]:
                return i + 1
            if not stack:
                return i + 1
        i += 1
    return len(text)


def _xml_end(text: str, start: int) -> int:
    """Naked XML owns payload quotes; nonstructural tokens cannot close it."""
    stack = []
    i = start
    while token := _XML_TOKEN.search(text, i):
        if token[0] != "<":
            terminator = "-->" if token[0] == "<!--" else "?>" if token[0] == "<?" else "]]>"
            end = text.find(terminator, token.end())
            if end == -1:
                return len(text)
            i = end + len(terminator)
            continue
        end = _tag_end(text, token.end())
        if end == len(text) and not text.endswith(">"):
            break
        tag = _XML_TAG.match(text, token.start())
        if not tag:
            i = end
            continue
        name = tag[2].lower()
        if tag[1]:
            if stack and stack[-1] == name:
                stack.pop()
                if not stack:
                    return end
        elif not text[tag.start():end].rstrip().endswith("/>"):
            stack.append(name)
        elif not stack:
            return end
        i = end
    # Unfinished raw tool XML owns EOF, including later literal-looking payloads.
    return len(text)


def _classified_spans(text: str):
    """Yield (start, end, evidence): outer literal or naked structure wins first."""
    i = 0
    while i < len(text):
        fence = _FENCE_START.match(text, i)
        if fence:
            marker = fence[1]
            close = re.compile(r"(?m)^ {0,3}" + re.escape(marker[0]) +
                               "{" + str(len(marker)) + r",}[ \t]*(?=\n|$)").search(text, fence.end())
            if not close:
                return
            yield i, close.end(), True
            i = close.end()
            continue
        quote = _BLOCKQUOTE.match(text, i)
        if quote:
            yield i, quote.end(), True
            i = quote.end()
            continue
        char = text[i]
        if char in "{[":
            end = _object_end(text, i)
            if _tool_envelope(text[i:end]):
                yield i, end, False
                i = end
                continue
            if char == "{":
                # Ordinary object field quotes are still syntax, never evidence.
                i = end
                continue
        if char == "<" and (tag := _XML_TAG.match(text, i)) and not tag[1]:
            end = _xml_end(text, i)
            yield i, end, False
            i = end
            continue
        if char == "`" and not _escaped(text, i):
            end = i
            while end < len(text) and text[end] == "`":
                end += 1
            marker = text[i:end]
            close = next((match for match in re.finditer(r"(?<!`)" + re.escape(marker) + r"(?!`)", text[end:])
                          if not _escaped(text, end + match.start())), None)
            if not close:
                return
            end += close.end()
            yield i, end, True
            i = end
            continue
        # Apostrophes, attribute delimiters and escaped quote marks are not openers.
        if char in "\"'" and not _escaped(text, i) and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] in "_=")):
            end = i + 1
            while end < len(text):
                if text[end] == "<":
                    tag_end = _tag_end(text, end + 1)
                    if tag_end < len(text) or text.endswith(">"):
                        end = tag_end
                        continue
                if text[end] == "\\":
                    end += 2
                    continue
                if text[end] == char and (end + 1 == len(text) or not text[end + 1].isalnum()):
                    yield i, end + 1, True
                    i = end + 1
                    break
                end += 1
            else:
                return
            continue
        i += 1


def clean_response(text: str) -> Optional[str]:
    """Preserve quoted evidence byte-for-byte; clean only unquoted spans."""
    if not text or not _LEAK_SNIFF.search(text):
        return None
    parts = []
    cursor = 0
    changed = False
    for start, end, evidence in list(_classified_spans(text)) + [(len(text), len(text), True)]:
        unquoted = text[cursor:start]
        cleaned = _clean_unquoted(unquoted)
        if cleaned is None:
            parts.append((unquoted, False))
        else:
            changed = True
            if cleaned != NO_REPLY:
                if parts:
                    cleaned = re.match(r"\s*", unquoted)[0] + cleaned
                if start < len(text):
                    cleaned += re.search(r"\s*$", unquoted)[0]
                parts.append((cleaned, False))
        if evidence:
            parts.append((text[start:end], True))
        else:
            changed = True
        cursor = end
    if not changed:
        return None
    # Trim only unprotected edges, never bytes belonging to evidence spans.
    parts = [(part, protected) for part, protected in parts if part]
    while parts and not parts[0][1]:
        part = parts[0][0].lstrip()
        if part:
            parts[0] = (part, False)
            break
        parts.pop(0)
    while parts and not parts[-1][1]:
        part = parts[-1][0].rstrip()
        if part:
            parts[-1] = (part, False)
            break
        parts.pop()
    result = "".join(part for part, _ in parts)
    return result if result.strip() else NO_REPLY


def _clean_unquoted(text: str) -> Optional[str]:
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
