"""Persistent, atomic host-integrity gauges. Only privileged producers write here."""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import re
import tempfile
import time

CHECKS = ("signatures", "store", "av")
FIELDS = ("last_attempt_seconds", "last_complete_seconds", "last_publish_seconds",
          "state", "findings", "skipped", "errors")


def atomic_write(path, content, mode):
    fd, temporary = tempfile.mkstemp(prefix=".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Reporter:
    def __init__(self, state_dir, metrics_dir, instance, check):
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]*", instance) or check not in CHECKS:
            raise ValueError("invalid integrity identity")
        self.instance, self.check = instance, check
        self.state_path = Path(state_dir) / f"{check}.json"
        self.metric_path = Path(metrics_dir) / f"{check}.prom"
        self.fields = FIELDS + (("signature_database_seconds",) if check == "signatures" else ())
        self.state_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.metric_path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
        os.chmod(self.state_path.parent, 0o700)

    def update(self, event, *, now=None, findings=0, skipped=0, errors=0, database_seconds=None):
        now = time.time() if now is None else now
        if event not in ("publish", "begin", "progress", "complete", "partial", "failed"):
            raise ValueError("invalid integrity event")
        for value in (now, findings, skipped, errors):
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError("invalid integrity value")
        if now > time.time():
            raise ValueError("future attempt time")
        if any(int(v) != v for v in (findings, skipped, errors)):
            raise ValueError("non-integer count")
        if database_seconds is not None and (self.check != "signatures" or
                type(database_seconds) not in (int, float) or
                not math.isfinite(database_seconds) or not 0 <= database_seconds <= now):
            raise ValueError("invalid signature database time")
        lock = os.open(self.state_path.with_suffix(".lock"), os.O_CREAT | os.O_RDWR, 0o600)
        with os.fdopen(lock, "w") as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            state = dict.fromkeys(self.fields, 0)
            if self.state_path.exists():
                state = json.loads(self.state_path.read_text())
                if set(state) != set(self.fields) or any(
                    type(v) not in (int, float) or not math.isfinite(v) or v < 0
                    for v in state.values()
                ) or state["state"] not in range(5) or any(
                    (key.endswith("_seconds") and value > now) or
                    (not key.endswith("_seconds") and int(value) != value)
                    for key, value in state.items()
                ):
                    raise ValueError("invalid persistent integrity state")
            if event == "begin":
                state.update(last_attempt_seconds=now, state=1, skipped=0, errors=0)
            elif event != "publish":
                if state["state"] != 1 or now < state["last_attempt_seconds"]:
                    raise ValueError("result requires a started attempt")
                state.update(state={"progress": 1, "complete": 2, "partial": 3, "failed": 4}[event],
                             findings=max(state["findings"], findings), skipped=skipped,
                             errors=max(errors, int(event == "failed")))
                if event == "complete":
                    if skipped or errors:
                        raise ValueError("complete coverage cannot have skipped items or errors")
                    state["last_complete_seconds"] = now
            if database_seconds is not None:
                state["signature_database_seconds"] = database_seconds
            state["last_publish_seconds"] = now
            # Persist first: interrupted metric publication is replayed on restart.
            atomic_write(self.state_path, json.dumps(state) + "\n", 0o600)
            labels = f'instance="{self.instance}",check="{self.check}"'
            metrics = "".join(f"host_integrity_{key}{{{labels}}} {state[key]}\n" for key in self.fields)
            atomic_write(self.metric_path, metrics, 0o644)
            return state


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--metrics-dir", required=True)
    parser.add_argument("--instance", required=True)
    parser.add_argument("--check", choices=CHECKS, required=True)
    args = parser.parse_args()
    Reporter(args.state_dir, args.metrics_dir, args.instance, args.check).update("publish")
