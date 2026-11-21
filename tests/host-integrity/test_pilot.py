"""Synthetic pilot resolution never changes real coverage or hides new findings."""
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import time

import pytest

ROOT = Path(__file__).resolve().parents[2]


def pilot():
    path = ROOT / "modules/services/_host-integrity-pilot.py"
    spec = importlib.util.spec_from_file_location("pilot", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def setup(tmp_path):
    module = pilot()
    cfg = dict(instance="fixture", check="av", state_dir=str(tmp_path / "state"),
               metrics_dir=str(tmp_path / "metrics"), scopeId="fixture-downloads", sourceRevision="fixture",
               retentionDays=30, maxReceipts=128, timeoutSeconds=10, outputMaxBytes=65536,
               work_dir=str(tmp_path / "work"), command=[os.environ.get("CLAMSCAN_BIN", "clamscan"),
               "--no-summary", "--stdout", "--alert-exceeds-max=yes", "--max-filesize=1024"])
    reporter = module.runner.reporter(cfg)
    reporter.update("begin", now=100)
    reporter.update("complete", now=101)
    reporter.update("begin", now=110)
    reporter.update("partial", now=111, findings=1, skipped=1, finding_source="synthetic")
    receipts = Path(cfg["state_dir"]) / "receipts"
    receipts.mkdir(mode=0o700)
    incident = dict(instance="fixture", check="av", scopeId="pilot-synthetic", started=110,
                    state="partial", counts=dict(findings=1, errors=0, skipped=1),
                    commandPolicy={"synthetic": True})
    clean = dict(instance="fixture", check="av", scopeId=cfg["scopeId"], started=120,
                 state="partial", counts=dict(findings=0, errors=0, skipped=2), commandPolicy={})
    for name, value in (("av-incident.json", incident), ("av-recovery.json", clean)):
        target = receipts / name
        target.write_text(json.dumps(value))
        target.chmod(0o600)
    reporter.update("begin", now=120)
    reporter.update("partial", now=121, skipped=2)
    review = dict(reviewer="fixture-operator", reason="Only the synthetic canary finding is resolved",
                  incidentReceipt="av-incident.json", recoveryReceipt="av-recovery.json")
    digest = hashlib.sha256(reporter.state_path.read_bytes()).hexdigest()
    return module, cfg, reporter, review, digest


def test_resolution_clears_only_synthetic_finding_and_retains_partial_coverage(tmp_path):
    module, cfg, r, review, digest = setup(tmp_path)
    before = json.loads(r.state_path.read_text())
    result = module.resolve(cfg, digest, review)
    assert result["findings"] == 0
    for field in ("state", "skipped", "errors", "last_attempt_seconds", "last_complete_seconds"):
        assert result[field] == before[field]
    audits = list((Path(cfg["state_dir"]) / "receipts").glob("av-resolution-*.json"))
    assert len(audits) == 1
    assert audits[0].stat().st_mode & 0o777 == 0o600
    assert json.loads(audits[0].read_text())["priorFindingResolved"] is True
    assert 'check="av"} 0' in r.metric_path.read_text()


def test_resolution_rejects_stale_review_without_mutating_state(tmp_path):
    module, cfg, r, review, digest = setup(tmp_path)
    r.update("publish", now=122)
    before = r.state_path.read_bytes()
    with pytest.raises(ValueError):
        module.resolve(cfg, digest, review)
    assert r.state_path.read_bytes() == before


def test_resolution_rejects_concurrent_job(tmp_path):
    module, cfg, r, review, digest = setup(tmp_path)
    with (Path(cfg["state_dir"]) / "av.run.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with pytest.raises(BlockingIOError):
            module.resolve(cfg, digest, review)


def test_resolution_rejects_any_later_genuine_finding(tmp_path):
    module, cfg, r, review, digest = setup(tmp_path)
    genuine = Path(cfg["state_dir"]) / "receipts/av-genuine.json"
    genuine.write_text(json.dumps(dict(instance="fixture", check="av", started=115,
                      commandPolicy={}, counts={"findings": 1})))
    genuine.chmod(0o600)
    with pytest.raises(ValueError):
        module.resolve(cfg, digest, review)


def test_resolution_requires_restricted_matching_zero_finding_receipt(tmp_path):
    module, cfg, r, review, digest = setup(tmp_path)
    recovery = Path(cfg["state_dir"]) / "receipts/av-recovery.json"
    recovery.chmod(0o644)
    with pytest.raises(ValueError):
        module.resolve(cfg, digest, review)


def test_harmless_real_scanner_canary_never_advances_real_scope_completion(tmp_path):
    module, cfg, r, review, digest = setup(tmp_path)
    cfg = dict(cfg, state_dir=str(tmp_path / "canary-state"), metrics_dir=str(tmp_path / "canary-metrics"))
    r = module.runner.reporter(cfg)
    r.update("begin", now=100)
    r.update("complete", now=101)
    before = json.loads(r.state_path.read_text())["last_complete_seconds"]
    module.canary(cfg, "finding")
    state = json.loads(r.state_path.read_text())
    assert state["findings"] == 1
    assert state["state"] == 3
    assert state["last_complete_seconds"] == before


@pytest.mark.parametrize("case,expected", [("partial", 3), ("error", 4)])
def test_harmless_canary_coverage_and_error_do_not_become_findings(tmp_path, case, expected):
    module, cfg, _, _, _ = setup(tmp_path)
    cfg = dict(cfg, state_dir=str(tmp_path / "case-state"), metrics_dir=str(tmp_path / "case-metrics"))
    r = module.runner.reporter(cfg)
    r.update("publish")
    module.canary(cfg, case)
    state = json.loads(r.state_path.read_text())
    assert state["state"] == expected
    assert state["findings"] == 0
    assert state["last_complete_seconds"] == 0


def test_resolution_audit_failure_cannot_clear_finding(tmp_path, monkeypatch):
    module, cfg, r, review, digest = setup(tmp_path)
    before = r.state_path.read_bytes()
    write = module.runner.report.atomic_write
    def fail_audit(path, content, mode):
        if path.name.startswith("av-resolution-"):
            raise OSError("fixture audit storage failure")
        return write(path, content, mode)
    monkeypatch.setattr(module.runner.report, "atomic_write", fail_audit)
    with pytest.raises(OSError):
        module.resolve(cfg, digest, review)
    assert r.state_path.read_bytes() == before


def test_resolution_rejects_genuine_progress_lost_before_final_receipt(tmp_path):
    module, cfg, r, review, _ = setup(tmp_path)
    r.update("begin", now=125)
    r.update("progress", now=126, findings=1)
    r.update("publish", now=127)
    r.update("begin", now=130)
    r.update("partial", now=131, skipped=2)
    recovery = Path(cfg["state_dir"]) / "receipts/av-recovery.json"
    record = json.loads(recovery.read_text())
    record["started"] = 130
    recovery.write_text(json.dumps(record))
    digest = hashlib.sha256(r.state_path.read_bytes()).hexdigest()
    with pytest.raises(ValueError):
        module.resolve(cfg, digest, review)
    assert json.loads(r.state_path.read_text())["findings"] == 1


def test_canary_refuses_genuine_evidence_persisted_before_counter_publication(tmp_path, monkeypatch):
    module, cfg, _, _, _ = setup(tmp_path)
    cfg = dict(cfg, state_dir=str(tmp_path / "crash-state"), metrics_dir=str(tmp_path / "crash-metrics"))
    r = module.runner.reporter(cfg)
    r.update("begin", now=100)
    with monkeypatch.context() as patch:
        def crash(state, now):
            raise OSError("fixture crash before state publication")
        patch.setattr(r, "_publish", crash)
        with pytest.raises(OSError):
            r.update("progress", now=101, findings=1)
    assert json.loads(r.state_path.read_text())["findings"] == 0
    r.update("publish", now=102)
    with pytest.raises(ValueError):
        module.canary(cfg, "finding")
