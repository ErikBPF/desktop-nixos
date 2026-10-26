"""Deterministic dedupe for repeated Grafana alert episodes (Argus/Cleytin).

Annotate-only: the plugin never suppresses a reply. It parses the rendered
Grafana Discord message, keeps a bounded JSON ledger, tells the model when an
episode is a repeat, and prefixes the reply with a stable marker.

No network, no subprocess, no tools. Every failure path returns None so a turn
is never broken or silenced by this plugin.
"""
from __future__ import annotations

import json
import logging
import os
import pathlib
import re
import sqlite3
import tempfile
import time
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger(__name__)

MODE_ENV = "ALERT_DEDUPE_MODE"
LEDGER_ENV = "ALERT_DEDUPE_LEDGER"
DB_ENV = "ALERT_DEDUPE_DB"
DEFAULT_LEDGER = "/opt/data/state/alert-dedupe/ledger.json"
DEFAULT_DB = "/opt/data/state.db"

MAX_EPISODES_PER_FAMILY = 5
MAX_FAMILIES = 2000
MAX_AGE_SECONDS = 30 * 24 * 3600
MAX_PENDING = 256

_INSTANCE_SPLIT = re.compile(r"(?m)^\s*(?=[\U0001F534\U0001F7E2])")
_RULE = re.compile(r"/alerting/grafana/([^/)#?]+)/view")
_HOST = re.compile(r"\*\*([^*]{1,80})\*\*")
_UNIT = re.compile(r"systemd unit ([\w@.:-]{1,96}\.service)")
_SINCE = re.compile(r"· since (\d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]{2,5})")
_SAFE = re.compile(r"[^A-Za-z0-9._:/-]+")

# (session_id, turn_id) -> Verdict for the current turn. Bounded FIFO.
_PENDING: dict[tuple[str, str], "Verdict"] = {}
_EMITTED: dict[tuple[str, str], str] = {}


@dataclass
class Instance:
    host: str
    severity: str
    rule: str
    since: str
    unit: str = ""
    resolved: bool = False

    @property
    def family(self) -> str:
        return "|".join(_clean(p) for p in (self.rule, self.host, self.unit or "-"))

    @property
    def label(self) -> str:
        parts = [self.rule, self.host]
        if self.unit:
            parts.append(self.unit)
        return " · ".join(p for p in parts if p)


@dataclass
class Verdict:
    kind: str  # none | new | new_episode | repeat | resolved | unknown
    instances: list[Instance] = field(default_factory=list)
    family: str = ""
    label: str = ""
    since: str = ""
    count: int = 0
    episode_count: int = 0
    prior_thread: Optional[str] = None


def _clean(value: str, limit: int = 64) -> str:
    return _SAFE.sub("-", value.strip())[:limit]


def _mode() -> str:
    return (os.environ.get(MODE_ENV) or "annotate").strip().lower()


def _ledger_path() -> pathlib.Path:
    return pathlib.Path(os.environ.get(LEDGER_ENV) or DEFAULT_LEDGER)


def parse_instances(text: str) -> list[Instance]:
    """Parse rendered Grafana Discord instances; [] when this is not an alert."""
    if not text:
        return []
    # Persisted text is prefixed with the sender label, e.g. "[Grafana] 🔴 ...".
    text = re.sub(r"^\s*\[[^\]\n]{1,40}\]\s*", "", text)
    rule_match = _RULE.search(text)
    if not rule_match:
        return []
    rule = _clean(rule_match.group(1))
    out: list[Instance] = []
    for block in _INSTANCE_SPLIT.split(text):
        block = block.strip()
        if not block or block[0] not in "\U0001F534\U0001F7E2":
            continue
        first, _, body = block.partition("\n")
        severity_match = re.search(r"\b(critical|warning|info)\b", first, re.I)
        since_match = _SINCE.search(block)
        if not since_match:
            continue
        host_match = _HOST.search(first)
        unit_match = _UNIT.search(body or first)
        out.append(
            Instance(
                host=host_match.group(1).strip() if host_match else "-",
                severity=(severity_match.group(1).lower() if severity_match else "unknown"),
                rule=rule,
                since=since_match.group(1),
                unit=unit_match.group(1) if unit_match else "",
                resolved=("Previous condition:" in block) or ("\U0001F7E2" in block[:2]),
            )
        )
    return out


class Ledger:
    def __init__(self, data: dict[str, Any], *, available: bool = True):
        self.data = data
        self.available = available

    @classmethod
    def load(cls) -> "Ledger":
        path = _ledger_path()
        if not path.exists():
            return cls({"version": 1, "families": {}})
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(raw, dict) or raw.get("version") != 1:
                raise ValueError("unsupported ledger shape")
            raw.setdefault("families", {})
            return cls(raw)
        except Exception as exc:  # corrupt or unreadable: degrade, never guess
            logger.warning("[alert-dedupe] ledger unreadable: %s", exc)
            return cls({"version": 1, "families": {}}, available=False)

    def episodes(self, family: str) -> list[dict[str, Any]]:
        return list(self.data.get("families", {}).get(family, {}).get("episodes", []))

    def find(self, family: str, since: str) -> Optional[dict[str, Any]]:
        for ep in reversed(self.episodes(family)):
            if ep.get("since") == since:
                return ep
        return None

    def latest_thread(self, family: str) -> Optional[str]:
        episodes = self.episodes(family)
        return episodes[-1].get("thread_id") if episodes else None

    def commit(self, verdict: Verdict, *, thread_id: Optional[str], now: Optional[float] = None) -> None:
        if not self.available or verdict.kind in ("none", "unknown"):
            return
        now = time.time() if now is None else now
        families = self.data.setdefault("families", {})
        if verdict.kind == "resolved":
            ep = self.find(verdict.family, verdict.since)
            if ep is not None:
                ep["resolved"] = True
                ep["last_seen"] = now
        else:
            fam = families.setdefault(verdict.family, {"episodes": []})
            ep = self.find(verdict.family, verdict.since)
            if ep is None:
                ep = {"since": verdict.since, "count": 0, "resolved": False, "thread_id": None}
                fam["episodes"].append(ep)
            ep["count"] = int(ep.get("count", 0)) + 1
            ep["resolved"] = False
            ep["last_seen"] = now
            if thread_id:
                ep["thread_id"] = str(thread_id)
            fam["episodes"] = fam["episodes"][-MAX_EPISODES_PER_FAMILY:]
        self._prune(now)
        self._save()

    def _prune(self, now: float) -> None:
        families = self.data.get("families", {})
        for name in list(families):
            episodes = [
                ep for ep in families[name].get("episodes", [])
                if now - float(ep.get("last_seen") or now) <= MAX_AGE_SECONDS
            ]
            if episodes:
                families[name]["episodes"] = episodes[-MAX_EPISODES_PER_FAMILY:]
            else:
                del families[name]
        if len(families) > MAX_FAMILIES:
            newest = sorted(
                families.items(),
                key=lambda kv: max((ep.get("last_seen") or 0) for ep in kv[1].get("episodes", [])),
                reverse=True,
            )[:MAX_FAMILIES]
            self.data["families"] = dict(newest)

    def _save(self) -> None:
        path = _ledger_path()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            os.chmod(path.parent, 0o700)
            fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".ledger.", text=True)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    json.dump(self.data, handle, separators=(",", ":"), sort_keys=True)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(tmp, path)
            finally:
                if os.path.exists(tmp):
                    os.unlink(tmp)
        except Exception as exc:  # annotation is best-effort
            logger.warning("[alert-dedupe] ledger write failed: %s", exc)


def classify(text: str, ledger: Ledger, *, thread_id: Optional[str] = None) -> Verdict:
    instances = parse_instances(text)
    if not instances:
        return Verdict(kind="none")
    if not ledger.available:
        return Verdict(kind="unknown", instances=instances)
    resolved = all(i.resolved for i in instances)
    if resolved:
        inst = instances[0]
        return Verdict(
            kind="resolved", instances=instances, family=inst.family,
            label=inst.label, since=inst.since,
        )

    kinds: list[str] = []
    counts: list[int] = []
    episode_counts: list[int] = []
    prior_thread = None
    for inst in instances:
        ep = ledger.find(inst.family, inst.since)
        if ep is not None and not ep.get("resolved"):
            kinds.append("repeat")
            counts.append(int(ep.get("count", 0)) + 1)
            episode_counts.append(len(ledger.episodes(inst.family)))
        elif ep is not None:
            kinds.append("new")  # same start after a resolve: Grafana restarted it
            counts.append(1)
            episode_counts.append(len(ledger.episodes(inst.family)) + 1)
            prior_thread = prior_thread or ep.get("thread_id")
        elif ledger.episodes(inst.family):
            kinds.append("new_episode")
            counts.append(1)
            episode_counts.append(len(ledger.episodes(inst.family)) + 1)
            prior_thread = prior_thread or ledger.latest_thread(inst.family)
        else:
            kinds.append("new")
            counts.append(1)
            episode_counts.append(1)

    if any(k == "new" for k in kinds):
        kind = "new"
    elif any(k == "new_episode" for k in kinds):
        kind = "new_episode"
    else:
        kind = "repeat"
    first = instances[0]
    return Verdict(
        kind=kind,
        instances=instances,
        family=first.family,
        label=first.label,
        since=first.since,
        count=max(counts),
        episode_count=max(episode_counts),
        prior_thread=prior_thread,
    )


def prior_thread(verdict: Verdict) -> Optional[str]:
    return verdict.prior_thread


def marker(verdict: Verdict) -> Optional[str]:
    if verdict.kind == "repeat":
        return f"repeat #{verdict.count} · {verdict.label} · since {verdict.since}"
    if verdict.kind == "new_episode":
        return f"new episode #{verdict.episode_count} · {verdict.label} · since {verdict.since}"
    if verdict.kind == "resolved":
        return f"resolved · {verdict.label} · since {verdict.since}"
    return None


def input_note(verdict: Verdict, prior_thread_id: Optional[str]) -> Optional[str]:
    link = f" Prior thread: <#{prior_thread_id}>." if prior_thread_id else ""
    if verdict.kind == "repeat":
        return (
            f"Alert ledger: this is repeat #{verdict.count} of {verdict.label} "
            f"(since {verdict.since}).{link} Reply with one short repeat line and do "
            "not re-investigate unless the payload shows a material change."
        )
    if verdict.kind == "new_episode":
        return (
            f"Alert ledger: new episode #{verdict.episode_count} of {verdict.label} "
            f"(since {verdict.since}); the earlier occurrence ended or restarted.{link} "
            "Investigate only what changed and link the prior episode."
        )
    if verdict.kind == "resolved":
        return (
            f"Alert ledger: this is a resolved notice for {verdict.label} "
            f"(since {verdict.since}). Reply with one short acknowledgement; do not "
            "investigate, and never archive or close a thread from a resolved event."
        )
    if verdict.kind == "unknown":
        return (
            "Alert ledger unavailable: repeat status cannot be confirmed. Do not "
            "claim a first sighting; say the repeat status is unconfirmed."
        )
    return None


def _session_thread(session_id: str) -> Optional[str]:
    db = os.environ.get(DB_ENV) or DEFAULT_DB
    if not session_id or not os.path.exists(db):
        return None
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=1.0)
        try:
            row = conn.execute("select thread_id from sessions where id = ?", (session_id,)).fetchone()
            return str(row[0]) if row and row[0] else None
        finally:
            conn.close()
    except Exception as exc:
        logger.debug("[alert-dedupe] session lookup failed: %s", exc)
        return None


def _remember(key: tuple[str, str], verdict: Verdict) -> None:
    if len(_PENDING) >= MAX_PENDING:
        _PENDING.pop(next(iter(_PENDING)), None)
    _PENDING[key] = verdict


def pre_llm_call(*, session_id: str = "", turn_id: str = "", user_message: Any = "",
                 platform: str = "", **_kw: Any) -> Optional[str]:
    try:
        if _mode() == "off" or not isinstance(user_message, str):
            return None
        ledger = Ledger.load()
        verdict = classify(user_message, ledger, thread_id=_session_thread(session_id))
        _remember((str(session_id), str(turn_id)), verdict)
        if verdict.kind == "none":
            return None
        if verdict.kind == "new":
            return None
        if verdict.kind == "unknown":
            return input_note(verdict, None)
        return input_note(verdict, verdict.prior_thread or ledger.latest_thread(verdict.family))
    except Exception as exc:  # fail-open
        logger.warning("[alert-dedupe] pre_llm_call failed: %s", exc)
        return None


def transform_llm_output(*, response_text: str = "", session_id: str = "",
                         turn_id: str = "", **_kw: Any) -> Optional[str]:
    key = (str(session_id), str(turn_id))
    try:
        if _mode() == "off" or not isinstance(response_text, str) or not response_text:
            return None
        if key in _EMITTED:
            return None
        verdict = _PENDING.pop(key, None)
        if verdict is None or verdict.kind in ("none", "unknown"):
            return None
        ledger = Ledger.load()
        ledger.commit(verdict, thread_id=_session_thread(session_id))
        text = marker(verdict)
        if not text:
            return None
        _EMITTED[key] = text
        if len(_EMITTED) > MAX_PENDING:
            _EMITTED.pop(next(iter(_EMITTED)), None)
        if response_text.startswith(text):
            return None
        return f"{text}\n\n{response_text}"
    except Exception as exc:  # fail-open: never suppress or break a reply
        logger.warning("[alert-dedupe] transform failed: %s", exc)
        if key in _EMITTED:
            return None
        return None


def register(ctx: Any) -> None:
    ctx.register_hook("pre_llm_call", pre_llm_call)
    ctx.register_hook("transform_llm_output", transform_llm_output)
