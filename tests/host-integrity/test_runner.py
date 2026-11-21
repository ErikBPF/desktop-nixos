"""Bounded jobs use fixture commands and temporary local scopes, never real scans."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import time

import pytest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "modules/services/_host-integrity-run.py"


def runner():
    assert HELPER.exists(), "bounded integrity runner is not implemented"
    spec = importlib.util.spec_from_file_location("integrity_run", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def config(tmp_path, check="store", body="exit 0"):
    tool = tmp_path / "tool"
    tool.write_text('#!/bin/sh\nif [ "$1" = --version ]; then echo fixture-1; exit 0; fi\n' + body + '\n')
    tool.chmod(0o755)
    db = tmp_path / "db"
    db.mkdir(exist_ok=True)
    for name in ("main", "daily", "bytecode"):
        (db / f"{name}.cvd").write_text(f"ClamAV-VDB:old-date:42:1:1:hash:signature:builder:{int(time.time()) - 864000}".ljust(512))
    scope = tmp_path / "scope"
    scope.mkdir(exist_ok=True)
    (scope / "sample").write_text("harmless fixture")
    return dict(instance="fixture", check=check, state_dir=str(tmp_path / "state"),
                metrics_dir=str(tmp_path / "metrics"), scopeId="fixture-scope", sourceRevision="fixture-rev",
                command=[str(tool)], databaseDirectory=str(db), paths=[str(scope)],
                timeoutSeconds=1, retentionDays=1, maxFileBytes=1024, maxScanBytes=2048,
                maxFiles=10, maxRecursion=5, outputMaxBytes=4096, maxReceipts=10,
                maxTotalBytes=4096, work_dir=str(tmp_path / "work"))


def state(cfg):
    return json.loads((Path(cfg["state_dir"]) / f'{cfg["check"]}.json').read_text())


@pytest.mark.parametrize("code,expected,findings", [(0,2,0),(1,2,1),(2,2,1),(3,2,1),(4,4,0),(5,4,1),(8,4,0)])
def test_store_exit_bitset_preserves_findings_and_coverage(tmp_path, code, expected, findings):
    run = runner()
    cfg = config(tmp_path, body=f"exit {code}")
    run.run(cfg)
    result = state(cfg)
    assert result["state"] == expected
    assert result["findings"] == findings
    assert bool(result["last_complete_seconds"]) == (expected == 2)


def test_deadline_records_failure(tmp_path):
    run = runner()
    cfg = config(tmp_path, body="sleep 30")
    started = time.monotonic()
    run.run(cfg)
    assert time.monotonic() - started < 4
    assert state(cfg)["state"] == 4
    assert state(cfg)["last_complete_seconds"] == 0


def test_noop_updater_does_not_refresh_database_time(tmp_path):
    run = runner()
    cfg = config(tmp_path, "signatures")
    old = int(time.time()) - 864000
    (Path(cfg["databaseDirectory"]) / "daily.cvd").write_text(f"ClamAV-VDB:old:42:1:1:h:s:b:{old}".ljust(512))
    run.run(cfg)
    assert state(cfg)["state"] == 2
    assert state(cfg)["signature_database_seconds"] == old
    receipt = json.loads(next((Path(cfg["state_dir"]) / "receipts").glob("*.json")).read_text())
    assert receipt["database"]["version"] == 42


@pytest.mark.parametrize("header", ["garbage", "ClamAV-VDB:future:42:1:1:h:s:b:999999999999"])
def test_invalid_database_metadata_is_failed_unknown(tmp_path, header):
    run = runner()
    cfg = config(tmp_path, "signatures")
    (Path(cfg["databaseDirectory"]) / "daily.cvd").write_text(header.ljust(512))
    run.run(cfg)
    assert state(cfg)["state"] == 4
    assert state(cfg)["signature_database_seconds"] == 0


@pytest.mark.parametrize("body,expected", [('echo "fixture: Eicar-Test-Signature FOUND"; exit 1', 2),
    ('echo "fixture: Heuristics.Limits.Exceeded FOUND"; exit 1', 3),
    ('echo "fixture: Heuristics.Encrypted.Zip FOUND"; exit 1', 3), ('exit 2', 4)])
def test_av_findings_and_coverage_gaps_are_distinct(tmp_path, body, expected):
    run = runner()
    cfg = config(tmp_path, "av", body)
    run.run(cfg)
    assert state(cfg)["state"] == expected
    assert bool(state(cfg)["last_complete_seconds"]) == (expected == 2)
    if "Heuristics" in body:
        assert state(cfg)["skipped"] == 1
        assert state(cfg)["findings"] == 0


def test_oversized_vanished_and_symlink_are_partial(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av")
    scope = Path(cfg["paths"][0])
    (scope / "oversized").write_bytes(b"x" * 2048)
    (scope / "link").symlink_to(scope / "sample")
    cfg["paths"].append(str(scope / "vanished"))
    run.run(cfg)
    assert state(cfg)["state"] == 3
    assert state(cfg)["skipped"] == 3
    assert state(cfg)["last_complete_seconds"] == 0


def test_positive_finding_survives_later_command_failure(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av", 'echo "fixture: malware FOUND"; echo "fixture: read failure ERROR"; exit 2')
    (Path(cfg["paths"][0]) / "z-error").write_text("fixture")
    run.run(cfg)
    assert state(cfg)["state"] == 4
    assert state(cfg)["findings"] == 1
    assert state(cfg)["last_complete_seconds"] == 0


def test_lock_conflict_does_not_launch_tool(tmp_path):
    run = runner()
    marker = tmp_path / "launched"
    cfg = config(tmp_path, body=f"touch '{marker}'")
    private = Path(cfg["state_dir"])
    private.mkdir()
    with (private / "store.run.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        run.run(cfg)
    assert not marker.exists()
    assert state(cfg)["state"] == 4


def test_receipt_expiry_does_not_delete_current_state(tmp_path):
    run = runner()
    cfg = config(tmp_path)
    receipts = Path(cfg["state_dir"]) / "receipts"
    receipts.mkdir(parents=True)
    old = receipts / "store-old.json"
    old.write_text('{}')
    os.utime(old, (1, 1))
    run.run(cfg)
    assert not old.exists()
    assert state(cfg)["state"] == 2
    receipt = next(receipts.glob("*.json"))
    assert receipt.stat().st_mode & 0o777 == 0o600
    assert receipts.stat().st_mode & 0o777 == 0o700


def test_whole_service_start_failure_becomes_visible(tmp_path):
    run = runner()
    cfg = config(tmp_path)
    run.service_failure(cfg, "resources")
    assert state(cfg)["state"] == 4
    assert state(cfg)["errors"] >= 1


def test_av_loads_database_once_for_multiple_files(tmp_path):
    run = runner()
    marker = tmp_path / "calls"
    cfg = config(tmp_path, "av", f"echo scan >> '{marker}'")
    (Path(cfg["paths"][0]) / "second").write_text("fixture")
    run.run(cfg)
    assert marker.read_text().splitlines() == ["scan"]


def test_mutable_path_swap_cannot_escape_scanner_scope(tmp_path, monkeypatch):
    run = runner()
    marker = tmp_path / "read-content"
    cfg = config(tmp_path, "av", f'''for a in "$@"; do
case "$a" in
--file-list=*) while IFS= read -r f; do cat "$f"; done < "${{a#*=}}";;
/*) cat "$a";;
esac
done > '{marker}' ''')
    source = Path(cfg["paths"][0]) / "sample"
    outside = tmp_path / "outside"
    outside.write_text("OUTSIDE SCOPE")
    invoke = run.command
    def swapped(argv, *args, **kwargs):
        if "--version" not in argv:
            source.unlink()
            source.symlink_to(outside)
        return invoke(argv, *args, **kwargs)
    monkeypatch.setattr(run, "command", swapped)
    run.run(cfg)
    assert "OUTSIDE SCOPE" not in marker.read_text()


def test_findings_survive_output_then_timeout_in_same_process(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av", 'echo "fixture: malware FOUND"; sleep 30')
    run.run(cfg)
    assert state(cfg)["state"] == 4
    assert state(cfg)["findings"] >= 1


def test_staging_has_private_source_mapping_and_cleans_abandoned_copy(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av")
    old = Path(cfg["work_dir"]) / "batch-abandoned"
    old.mkdir(parents=True)
    (old / "0").write_text("stale private copy")
    run.run(cfg)
    assert not old.exists()
    receipt = json.loads(next((Path(cfg["state_dir"]) / "receipts").glob("*.json")).read_text())
    assert str(Path(cfg["paths"][0]) / "sample") in json.dumps(receipt["details"])
    assert not list(Path(cfg["work_dir"]).iterdir())


def test_aggregate_copy_limit_is_partial(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av")
    cfg["maxTotalBytes"] = 1
    run.run(cfg)
    assert state(cfg)["state"] == 3
    assert state(cfg)["last_complete_seconds"] == 0


def test_unreadable_policy_uses_actual_open_failure_even_as_root(tmp_path, monkeypatch):
    run = runner()
    cfg = config(tmp_path, "av")
    original = run.open_local
    def unreadable(path, directory=-100):
        if path == "sample":
            raise PermissionError("fixture unreadable")
        return original(path, directory)
    monkeypatch.setattr(run, "open_local", unreadable)
    run.run(cfg)
    assert state(cfg)["state"] == 3
    assert state(cfg)["skipped"] == 1


def test_deadline_kills_child_when_parent_already_exited(tmp_path):
    run = runner()
    child_file = tmp_path / "child"
    cfg = config(tmp_path, body=f'sleep 30 &\necho $! > "{child_file}"\nexit 0')
    run.run(cfg)
    pid = int(child_file.read_text())
    try:
        status = Path(f"/proc/{pid}/stat").read_text().split()[2]
        assert status == "Z", "live descendant survived deadline"
    except FileNotFoundError:
        pass
    finally:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def test_invalid_scanner_output_is_failed_even_with_scope_exclusion(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av", "echo unexplained; exit 1")
    cfg["paths"].append(str(tmp_path / "missing"))
    run.run(cfg)
    assert state(cfg)["state"] == 4


def test_receipt_retention_cannot_expire_another_checks_evidence(tmp_path):
    run = runner()
    cfg = config(tmp_path)
    directory = Path(cfg["state_dir"]) / "receipts"
    directory.mkdir(parents=True)
    peer = directory / "av-old.json"
    peer.write_text('{}')
    os.utime(peer, (1, 1))
    run.run(cfg)
    assert peer.exists()


def test_service_failure_writes_restricted_receipt(tmp_path):
    run = runner()
    cfg = config(tmp_path)
    run.service_failure(cfg, "resources")
    receipts = list((Path(cfg["state_dir"]) / "receipts").glob("*.json"))
    assert len(receipts) == 1
    assert json.loads(receipts[0].read_text())["state"] == "failed"


def test_timeout_receipt_retains_observed_signature_for_resolution(tmp_path):
    run = runner()
    cfg = config(tmp_path, "av", 'echo "0: Fixture-Signature FOUND"; sleep 30')
    run.run(cfg)
    receipt = next((Path(cfg["state_dir"]) / "receipts").glob("*.json")).read_text()
    assert "Fixture-Signature" in receipt


def test_database_update_cannot_overlap_scan(tmp_path):
    run = runner()
    marker = tmp_path / "updated"
    cfg = config(tmp_path, "signatures", f"touch '{marker}'")
    private = Path(cfg["state_dir"])
    private.mkdir()
    with (private / "database.run.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_SH)
        run.run(cfg)
    assert not marker.exists()
    assert state(cfg)["state"] == 4


@pytest.mark.parametrize("check", ["store", "av"])
def test_heavy_checks_do_not_overlap(tmp_path, check):
    run = runner()
    marker = tmp_path / "heavy-launched"
    cfg = config(tmp_path, check, f"touch '{marker}'")
    private = Path(cfg["state_dir"])
    private.mkdir()
    with (private / "heavy.run.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        run.run(cfg)
    assert not marker.exists()
    assert state(cfg)["state"] == 4


def test_handled_tool_failure_publishes_failed_state_with_normal_exit(tmp_path):
    import subprocess
    import sys
    cfg = config(tmp_path, body="exit 4")
    configuration = tmp_path / "job.json"
    configuration.write_text(json.dumps(cfg))
    result = subprocess.run([sys.executable, str(HELPER), "--config", str(configuration)],
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    assert state(cfg)["state"] == 4
    assert state(cfg)["errors"] == 1


@pytest.mark.parametrize("missing", ["main", "bytecode"])
def test_partial_database_install_cannot_be_reported_complete(tmp_path, missing):
    run = runner()
    marker = tmp_path / "scan-started"
    cfg = config(tmp_path, "av", f"touch '{marker}'")
    (Path(cfg["databaseDirectory"]) / f"{missing}.cvd").unlink()
    run.run(cfg)
    assert state(cfg)["state"] == 4
    assert state(cfg)["last_complete_seconds"] == 0
    assert not marker.exists()
