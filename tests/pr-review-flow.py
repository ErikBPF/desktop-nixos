#!/usr/bin/env python3
"""Contract check for the PR review collector, ledger and queue metrics.

Synthetic only. No GitHub calls, tokens, or host state.
"""

import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts/pr-review"
sys.path.insert(0, str(SCRIPTS))

import ledger


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


collect = load(SCRIPTS / "collect.py", "pr_review_collect")
publish = load(SCRIPTS / "publish.py", "pr_review_publish")
metrics = load(SCRIPTS / "metrics.py", "pr_review_metrics")


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def test_ledger_uses_wal():
    with tempfile.TemporaryDirectory() as tmp:
        db = ledger.connect(Path(tmp) / "ledger.db")
        try:
            mode = db.execute("PRAGMA journal_mode").fetchone()[0]
            check(mode == "wal", f"journal_mode={mode}")
        finally:
            db.close()


def test_latest_published_bundles_keeps_newest_per_pr():
    with tempfile.TemporaryDirectory() as tmp:
        db = ledger.connect(Path(tmp) / "ledger.db")
        try:
            rows = [
                ("r/a", 1, "aaaa111", "bundle-old", "published", 100),
                ("r/a", 1, "aaaa222", "bundle-new", "published", 200),
                ("r/a", 2, "bbbb111", "bundle-only", "published", 150),
                ("r/a", 3, "cccc111", "bundle-stale", "stale", 300),
                ("r/b", 1, "dddd111", "bundle-other", "published", 400),
            ]
            for repo, pr, head, bundle, state, updated in rows:
                db.execute(
                    "INSERT INTO reviews (repo, pr, head, bundle, state, "
                    "requested_at, updated_at) VALUES (?,?,?,?,?,?,?)",
                    (repo, pr, head, bundle, state, updated, updated),
                )
            kept = ledger.latest_published_bundles(db, "r/a")
            check(
                kept == {"bundle-new", "bundle-only"},
                f"unexpected retention set {sorted(kept)}",
            )
        finally:
            db.close()


def test_settle_gate_waits_for_a_stable_head():
    seen = {}
    current = {}
    check(
        collect.settle_gate(seen, current, "r#1", "aaa", 5) is False,
        "a first sighting must not bundle immediately",
    )
    check(current["r#1"][0] == "aaa", "the head must be recorded")
    # Same head, still inside the window.
    check(
        collect.settle_gate(current, {}, "r#1", "aaa", 5) is False,
        "a head inside the window must keep waiting",
    )
    # Same head, window elapsed.
    old = {"r#1": ["aaa", time.time() - 6 * 60]}
    check(
        collect.settle_gate(old, {}, "r#1", "aaa", 5) is True,
        "a head that outlived the window must bundle",
    )
    # A newer head restarts the window.
    check(
        collect.settle_gate(old, {}, "r#1", "bbb", 5) is False,
        "a new head must restart the settle window",
    )
    # 0 disables the gate.
    check(
        collect.settle_gate({}, {}, "r#1", "ccc", 0) is True,
        "settle_minutes=0 must bundle immediately",
    )


def test_prune_done_bundles_retains_newest_and_reusable():
    with tempfile.TemporaryDirectory() as tmp:
        data = Path(tmp)
        done = data / "review-done"
        done.mkdir()
        db = ledger.connect(data / "ledger.db")
        try:
            bundle = ledger.bundle_id("r/a", 1, "aaaa111")
            db.execute(
                "INSERT INTO reviews (repo, pr, head, bundle, state, "
                "requested_at, updated_at) VALUES ('r/a',1,'aaaa111',?,'published',1,1)",
                (bundle,),
            )
            names = []
            for index in range(5):
                name = f"r__a__{index + 10}____{index}"
                (done / name).mkdir()
                (done / f"{name}.json").write_text("{}")
                (done / name).touch()
                os.utime(done / name, (1000 + index, 1000 + index))
                names.append(name)
            # The protected bundle was published a week ago: older than all.
            (done / bundle).mkdir()
            (done / f"{bundle}.json").write_text("{}")
            os.utime(done / bundle, (1, 1))

            removed = collect.prune_done_bundles(done, db, "r/a", 2)
            remaining = {path.name for path in done.iterdir() if path.is_dir()}
            check(removed == 3, f"removed={removed}")
            check(bundle in remaining, "the reusable bundle must survive")
            check(
                remaining == {bundle, names[-1], names[-2]},
                f"unexpected survivors {sorted(remaining)}",
            )
            check(
                not (done / f"{names[0]}.json").exists(),
                "the packet of a pruned bundle must go with it",
            )
        finally:
            db.close()


def delta_compare(status="ahead", files=None):
    return {
        "status": status,
        "files": files
        if files is not None
        else [
            {
                "filename": "src/app.py",
                "status": "modified",
                "additions": 2,
                "deletions": 1,
                "patch": "@@ -1,2 +1,3 @@\n keep\n-drop\n+add\n+more",
            }
        ],
    }


def test_build_delta_renders_a_patch():
    collect.gh_json = lambda args, token: delta_compare()
    patch = collect.build_delta("r/a", "a" * 40, "b" * 40, "t")
    check(patch is not None, "an ancestor comparison must produce a delta")
    check("diff --git a/src/app.py" in patch, "the file header must be present")
    check("+more" in patch, "the hunk body must be present")


def test_build_delta_falls_back_to_the_full_diff():
    cases = {
        "force-push": delta_compare(status="diverged"),
        "no files": {"status": "ahead", "files": []},
        "binary file": {
            "status": "ahead",
            "files": [{"filename": "logo.png", "status": "added"}],
        },
        "truncated": {
            "status": "ahead",
            "files": [
                {"filename": f"f{index}", "patch": "@@ -1 +1 @@"}
                for index in range(300)
            ],
        },
    }
    for label, payload in cases.items():
        collect.gh_json = lambda args, token, payload=payload: payload
        check(
            collect.build_delta("r/a", "a" * 40, "b" * 40, "t") is None,
            f"{label} must fall back to the full diff",
        )


def test_request_bypasses_the_settle_window():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        data = root / "data"
        state = root / "state"
        state.mkdir()
        ledger_path = data / "review-ledger" / "ledger.db"
        ledger.connect(ledger_path).close()
        head = "b" * 40
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "request.py"),
                "--ledger",
                str(ledger_path),
                "--data-dir",
                str(data),
                "--state-dir",
                str(state),
                "--repo",
                "r/a",
                "--pr",
                "7",
                "--head",
                head,
            ],
            text=True,
            capture_output=True,
        )
        check(proc.returncode == 0, proc.stderr)
        check("NO-REVIEW" in proc.stdout, proc.stdout)
        settle = json.loads((state / "settle.json").read_text())
        check(
            settle == {"r/a#7": [head, 0]},
            f"an explicit request must look settled, got {settle}",
        )
        check(
            collect_settle_ready(settle, "r/a#7", head, 5) is True,
            "the collector must bundle a requested head immediately",
        )


def collect_settle_ready(seen, key, head, minutes):
    current = {}
    return collect.settle_gate(seen, current, key, head, minutes)


def test_publish_accepts_delta_evidence():
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp)
        (bundle / "delta.patch").write_text(
            "diff --git a/x b/x\n+token = os.environ['NOPE']\n"
        )
        check(
            publish.evidence_in_bundle("token = os.environ['NOPE']", bundle),
            "a delta quote must satisfy evidence validation",
        )
        check(
            not publish.evidence_in_bundle("never in the bundle", bundle),
            "an absent quote must still fail",
        )


EXECUTIONS_SCHEMA = """
CREATE TABLE executions (
  id TEXT PRIMARY KEY, job_id TEXT NOT NULL, source TEXT NOT NULL,
  process_id TEXT NOT NULL, pid INTEGER NOT NULL,
  process_started_at INTEGER, status TEXT NOT NULL,
  claimed_at TEXT NOT NULL, started_at TEXT, finished_at TEXT, error TEXT
)
"""


def test_metrics_describe_the_queue():
    with tempfile.TemporaryDirectory() as tmp:
        data = Path(tmp)
        (data / "review-ledger").mkdir()
        (data / "cron").mkdir()
        textfile = data / "textfile"
        textfile.mkdir()

        db = ledger.connect(data / "review-ledger" / "ledger.db")
        now = time.time()
        try:
            for repo, pr, head, state, requested in (
                ("r/a", 1, "aaa", "queued", now - 600),
                ("r/a", 2, "bbb", "leased", now - 60),
                ("r/a", 3, "ccc", "published", now - 30),
                ("r/a", 4, "ddd", "stale", now - 5000),
            ):
                db.execute(
                    "INSERT INTO reviews (repo, pr, head, bundle, state, "
                    "requested_at, updated_at, lease_expires) "
                    "VALUES (?,?,?,?,?,?,?,?)",
                    (
                        repo,
                        pr,
                        head,
                        ledger.bundle_id(repo, pr, head),
                        state,
                        requested,
                        now,
                        now + 1800 if state == "leased" else None,
                    ),
                )
        finally:
            db.close()

        exec_db = sqlite3.connect(data / "cron" / "executions.db")
        exec_db.executescript(EXECUTIONS_SCHEMA)
        exec_db.execute(
            "INSERT INTO executions (id, job_id, source, process_id, pid, status, "
            "claimed_at) VALUES ('e1','j1','builtin','p1',1,'failed',?)",
            (time.strftime("%Y-%m-%dT%H:%M:%S.000000+00:00", time.gmtime()),),
        )
        exec_db.commit()
        exec_db.close()

        argv = sys.argv
        sys.argv = [
            "metrics",
            "--data-dir",
            str(data),
            "--textfile-dir",
            str(textfile),
        ]
        try:
            check(metrics.main() == 0, "metrics must exit 0")
        finally:
            sys.argv = argv

        text = (textfile / "hermes-pr-review.prom").read_text()
        check(
            'hermes_pr_review_queue_depth{state="queued"} 1' in text,
            "queued depth missing",
        )
        check(
            'hermes_pr_review_queue_depth{state="claimable"} 1' in text,
            "a live lease must not count as claimable",
        )
        check(
            'hermes_pr_review_queue_depth{state="stale"} 1' in text,
            "stale depth missing",
        )
        check(
            "hermes_pr_review_oldest_wait_seconds 600" in text,
            "oldest wait missing",
        )
        check(
            'hermes_pr_review_published{window="15m"} 1' in text,
            "published window missing",
        )
        check(
            'hermes_pr_review_executions{source="builtin",status="failed"} 1' in text,
            "execution outcomes missing",
        )


def main():
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
        print(f"ok {test.__name__}")
    print(f"{len(tests)} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
