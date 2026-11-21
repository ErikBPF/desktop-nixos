"""Behavioral contract for the persistent integrity publication boundary."""
import importlib.util
import json
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "modules/services/_host-integrity-report.py"


def load_reporting():
    assert HELPER.exists(), "persistent integrity reporter is not implemented"
    spec = importlib.util.spec_from_file_location("integrity_report", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reporter(reporting, tmp_path, check="store"):
    return reporting.Reporter(tmp_path / "private", tmp_path / "metrics", "fixture", check)


def test_never_run_and_private_state(tmp_path):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("publish", now=100)
    state = json.loads(r.state_path.read_text())
    assert state["state"] == 0
    assert state["last_complete_seconds"] == 0
    assert r.state_path.stat().st_mode & 0o777 == 0o600
    assert r.state_path.parent.stat().st_mode & 0o777 == 0o700
    assert r.metric_path.stat().st_mode & 0o777 == 0o644
    text = r.metric_path.read_text()
    assert 'host_integrity_state{instance="fixture",check="store"} 0\n' in text
    assert "signature_database" not in text
    assert text.count("{instance=") == 7


def test_restart_failure_and_clean_run_retain_coverage_and_findings(tmp_path):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("begin", now=100)
    r.update("complete", now=101, findings=2)
    r = reporter(reporting, tmp_path)
    r.update("begin", now=110)
    state = r.update("failed", now=111, skipped=3, findings=1)
    assert state["last_complete_seconds"] == 101
    assert state["findings"] == 2
    assert state["errors"] == 1
    assert state["skipped"] == 3
    r.update("begin", now=120)
    state = r.update("complete", now=121)
    assert state["findings"] == 2
    assert state["last_complete_seconds"] == 121
    assert state["errors"] == state["skipped"] == 0


def test_partial_does_not_advance_complete(tmp_path):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("begin", now=100)
    state = r.update("partial", now=101, skipped=2)
    assert state["state"] == 3
    assert state["last_complete_seconds"] == 0


@pytest.mark.parametrize("kwargs", [{"findings": -1}, {"errors": float("nan")},
                                    {"now": float("inf")}, {"database_seconds": 999999999999},
                                    {"labels": {"instance": "forged"}}])
def test_reject_invalid_input_without_replacing_output(tmp_path, kwargs):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path, "signatures")
    r.update("begin", now=100)
    before = r.metric_path.read_bytes()
    with pytest.raises((ValueError, TypeError)):
        r.update("complete", **({"now": 101} | kwargs))
    assert r.metric_path.read_bytes() == before


def test_reject_identity_and_check_injection(tmp_path):
    reporting = load_reporting()
    for instance, check in [('bad"host', 'store'), ('fixture', 'arbitrary')]:
        with pytest.raises(ValueError):
            reporting.Reporter(tmp_path / "private", tmp_path / "metrics", instance, check)


def test_interrupted_metric_replace_is_atomic_and_recovers_from_state(tmp_path, monkeypatch):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("begin", now=100)
    before = r.metric_path.read_bytes()
    replace = os.replace
    def interrupted(source, target):
        if Path(target) == r.metric_path:
            assert r.metric_path.read_bytes() == before
            raise OSError("fixture interrupted publication")
        replace(source, target)
    monkeypatch.setattr(reporting.os, "replace", interrupted)
    with pytest.raises(OSError):
        r.update("complete", now=101, findings=4)
    assert r.metric_path.read_bytes() == before
    monkeypatch.setattr(reporting.os, "replace", replace)
    state = reporter(reporting, tmp_path).update("publish", now=102)
    assert state["findings"] == 4
    assert state["last_complete_seconds"] == 101
    assert not list(r.metric_path.parent.glob("*.tmp"))


def test_corrupt_state_is_not_silently_reset(tmp_path):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("begin", now=100)
    r.state_path.write_text('{"findings": 99}')
    before = r.metric_path.read_bytes()
    with pytest.raises(ValueError):
        r.update("publish", now=102)
    assert r.metric_path.read_bytes() == before


@pytest.mark.parametrize("field,value", [("last_complete_seconds", 999999999999),
                                         ("findings", 1.5), ("errors", True)])
def test_reject_malformed_persistent_values(tmp_path, field, value):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("publish", now=100)
    state = json.loads(r.state_path.read_text())
    state[field] = value
    r.state_path.write_text(json.dumps(state))
    with pytest.raises(ValueError):
        r.update("publish", now=101)


def test_boolean_database_time_cannot_poison_persistent_state(tmp_path):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path, "signatures")
    r.update("begin", now=100)
    state_before, metrics_before = r.state_path.read_bytes(), r.metric_path.read_bytes()
    with pytest.raises(ValueError):
        r.update("complete", now=101, database_seconds=True)
    assert r.state_path.read_bytes() == state_before
    assert r.metric_path.read_bytes() == metrics_before
    assert r.update("publish", now=102)["state"] == 1


def test_running_progress_persists_findings_before_later_service_failure(tmp_path):
    reporting = load_reporting()
    r = reporter(reporting, tmp_path)
    r.update("begin", now=100)
    state = r.update("progress", now=101, findings=2, skipped=1)
    assert state["state"] == 1
    assert state["findings"] == 2
    assert reporter(reporting, tmp_path).update("failed", now=102)["findings"] == 2
