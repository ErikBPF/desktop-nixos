#!/usr/bin/env python3
"""Contract check for the PR review publisher and ready probe.

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
PUBLISH = SCRIPTS / "publish.py"
GATE = SCRIPTS / "apply-gate.py"
REQUEST = SCRIPTS / "request.py"
sys.path.insert(0, str(SCRIPTS))

import ledger
import tokens


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pub = load(PUBLISH, "pr_review_publish")
gate = load(GATE, "pr_review_gate")


def review(**overrides):
    data = {
        "repo": "apache/datafusion-comet",
        "pr": 6945,
        "base": "b" * 40,
        "head": "a" * 40,
        "routed_skills": ["review-comet-pr"],
        "summary": "Native bitmap path preserves compression.",
        "findings": [
            {
                "id": "f1",
                "severity": "P2",
                "file": "native/src/lib.rs",
                "line": 12,
                "title": "Second finding",
                "body": "Body two.",
                "evidence": "let value = other;",
                "action": "Do the second thing.",
            },
            {
                "id": "f2",
                "severity": "P1",
                "file": "spark/src/Main.scala",
                "line": 7,
                "title": "First finding",
                "body": "Body one.",
                "evidence": "let value = 1;",
                "action": "Do the first thing.",
            },
        ],
        "validation": ["Compared the diff with the source."],
        "limits": ["No build."],
    }
    data.update(overrides)
    return data


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    bundle = tmp / "bundle"
    bundle.mkdir()
    (bundle / "diff.patch").write_text(
        "diff --git a/native/src/lib.rs b/native/src/lib.rs\n"
        "+let value = 1;\n"
        "+let value = other;\n"
    )

    parsed, errors = pub.validate(review())
    assert not errors, errors
    body = pub.render(parsed, parsed["repo"])
    assert body.startswith("## Automated review"), body[:60]
    assert "### P1" in body and body.index("### P1") < body.index("### P2")
    assert "let value = 1;" in body
    assert f"{pub.MARKER}{'a' * 40}:" in body
    assert "approves only when it found no P1/P2" in body
    assert pub.verdict(parsed["findings"]) == "failure"
    assert pub.review_event(parsed["findings"]) == "REQUEST_CHANGES"
    assert pub.verdict([]) == "success"
    assert pub.review_event([]) == "APPROVE"

    _, errors = pub.validate(review(findings=[
        dict(review()["findings"][0], severity="P3")
    ]))
    assert errors, "P3 must be rejected"

    _, errors = pub.validate(review(findings=[
        dict(review()["findings"][0], evidence="")
    ]))
    assert errors, "empty evidence must be rejected"

    assert pub.evidence_in_bundle("let value = 1;", bundle)
    assert not pub.evidence_in_bundle("fabricated claim", bundle)

    empty = review(findings=[])
    parsed, errors = pub.validate(empty)
    assert not errors, errors
    assert "No new P1/P2 findings" in pub.render(parsed, parsed["repo"])

    # Leases live in a ledger; the agent never needs write access to review-in.
    review_in = tmp / "in"
    review_out = tmp / "out"
    ledger_path = tmp / "ledger.db"
    review_in.mkdir()
    review_out.mkdir()
    claim_script = SCRIPTS / "claim.py"
    db = ledger.connect(ledger_path)

    def claim(*extra):
        result = subprocess.run(
            [str(claim_script), "--worker", "w1", *extra],
            env=dict(
                os.environ,
                HERMES_REVIEW_IN=str(review_in),
                HERMES_REVIEW_OUT=str(review_out),
                HERMES_REVIEW_LEDGER=str(ledger_path),
            ),
            text=True,
            capture_output=True,
            check=True,
        )
        return result.stdout.strip().splitlines()[0]

    older = review_in / "older"
    newer = review_in / "newer"
    for bundle, mtime in ((older, 1_000_000), (newer, 2_000_000)):
        bundle.mkdir()
        (bundle / ".ready").write_text("now\n")
        os.utime(bundle, (mtime, mtime))
    ledger.record(db, "ErikBPF/aster", 1, "a" * 40, "", "older")
    ledger.record(db, "ErikBPF/aster", 1, "b" * 40, "", "newer")

    assert claim() == "CLAIM newer", "a newer head supersedes the older one"
    assert claim() == "NO_CLAIM", "each worker gets a distinct head"

    db.execute("UPDATE reviews SET lease_expires = 0 WHERE bundle = 'newer'")
    assert claim("--claim-ttl", "1") == "CLAIM newer", "expired lease is reclaimable"

    # A head is never reviewed twice after it published.
    ledger.finish(db, "ErikBPF/aster", 1, "a" * 40, "published")
    ledger.finish(db, "ErikBPF/aster", 1, "b" * 40, "published")
    assert claim() == "NO_CLAIM"

    # Repeated expired leases stop after max attempts instead of retrying forever.
    capped = review_in / "capped"
    capped.mkdir()
    (capped / ".ready").write_text("now\n")
    ledger.record(db, "ErikBPF/aster", 2, "c" * 40, "", "capped")
    assert claim("--claim-ttl", "1") == "CLAIM capped"
    for _ in range(2):
        db.execute("UPDATE reviews SET lease_expires = 0 WHERE bundle = 'capped'")
        assert claim("--claim-ttl", "1") == "CLAIM capped"
    db.execute("UPDATE reviews SET lease_expires = 0 WHERE bundle = 'capped'")
    assert claim("--claim-ttl", "1") == "NO_CLAIM"
    row = db.execute("SELECT state FROM reviews WHERE bundle = 'capped'").fetchone()
    assert row["state"] == "failed"

    # A retry resets the attempt budget; without that the 45-minute requeue
    # oscillates failed -> queued -> failed and never reviews the head.
    ledger.requeue(db, "ErikBPF/aster", 2, "c" * 40)
    row = ledger.get(db, "ErikBPF/aster", 2, "c" * 40)
    assert row["state"] == "queued" and row["attempts"] == 0
    assert claim() == "CLAIM capped", "a requeued head must be claimable again"

    # Published is terminal: a late duplicate packet cannot downgrade it.
    ledger.finish(db, "ErikBPF/aster", 2, "c" * 40, "published")
    ledger.finish(db, "ErikBPF/aster", 2, "c" * 40, "failed", "late packet")
    row = ledger.get(db, "ErikBPF/aster", 2, "c" * 40)
    assert row["state"] == "published"

    # A stale head that is still open at the same commit can be revived.
    ledger.record(db, "ErikBPF/aster", 3, "d" * 40, "", "revive")
    ledger.finish(db, "ErikBPF/aster", 3, "d" * 40, "stale", "closed")
    ledger.requeue(db, "ErikBPF/aster", 3, "d" * 40)
    row = ledger.get(db, "ErikBPF/aster", 3, "d" * 40)
    assert row["state"] == "queued" and row["attempts"] == 0

    # A published head whose root-only marker went missing is reviewable again.
    ledger.record(db, "ErikBPF/aster", 4, "e" * 40, "", "missing-marker")
    ledger.finish(db, "ErikBPF/aster", 4, "e" * 40, "published")
    ledger.requeue(db, "ErikBPF/aster", 4, "e" * 40)
    row = ledger.get(db, "ErikBPF/aster", 4, "e" * 40)
    assert row["state"] == "queued" and row["attempts"] == 0

    # A missing inbox must not stale the whole queue.
    missing = subprocess.run(
        [str(claim_script), "--worker", "w1"],
        env=dict(
            os.environ,
            HERMES_REVIEW_IN=str(tmp / "absent"),
            HERMES_REVIEW_LEDGER=str(ledger_path),
        ),
        text=True,
        capture_output=True,
        check=True,
    )
    missing_lines = missing.stdout.strip().splitlines()
    assert missing_lines[0] == "NO_CLAIM"
    assert missing_lines[-1] == '{"wakeAgent": false}'

    # Superseded and closed-PR bundles are pruned; a live lease is preserved.
    collect = load(SCRIPTS / "collect.py", "pr_review_collect")
    keep = review_in / "ErikBPF__aster__1__aaaaaaaaaaaa"
    superseded = review_in / "ErikBPF__aster__1__eeeeeeeeeeee"
    closed = review_in / "ErikBPF__aster__2__cccccccccccc"
    busy = review_in / "ErikBPF__aster__1__dddddddddddd"
    for bundle in (keep, superseded, closed, busy):
        bundle.mkdir()
    ledger.record(db, "ErikBPF/aster", 1, "e" * 40, "", superseded.name)
    ledger.record(db, "ErikBPF/aster", 2, "c" * 40, "", closed.name)
    ledger.record(db, "ErikBPF/aster", 1, "d" * 40, "", busy.name)
    db.execute(
        "UPDATE reviews SET state = 'leased', lease_expires = ? WHERE bundle = ?",
        (time.time() + 3600, busy.name),
    )
    removed = collect.prune_repo_bundles(
        review_in, db, "ErikBPF/aster", {1: "a" * 40}
    )
    assert removed == 2, removed
    assert keep.exists() and busy.exists()
    assert not superseded.exists() and not closed.exists()

    # Pruning a superseded reuse also drops its packet, so the publisher does
    # not report a bundle-less identity mismatch.
    prune_root = tmp / "prune-reuse"
    prune_bundle = "ErikBPF__aster__50__999999999999"
    (prune_root / "review-in" / prune_bundle).mkdir(parents=True)
    (prune_root / "review-out").mkdir(parents=True)
    (prune_root / "review-out" / f"{prune_bundle}.json").write_text("{}\n")
    ledger.mark_reusing(
        db, "ErikBPF/aster", 50, "9" * 40, "", prune_bundle, "k" * 64
    )
    collect.prune_repo_bundles(prune_root / "review-in", db, "ErikBPF/aster", {})
    assert not (prune_root / "review-out" / f"{prune_bundle}.json").exists()

    # A failed head whose PR merged or closed becomes stale, not retried.
    ledger.record(db, "ErikBPF/aster", 99, "f" * 40, "", "gone")
    ledger.finish(db, "ErikBPF/aster", 99, "f" * 40, "failed", "bundle missing")
    assert collect.reconcile_closed(db, "ErikBPF/aster", {1, 2, 3, 4}) == 1
    row = db.execute("SELECT state FROM reviews WHERE pr = 99").fetchone()
    assert row["state"] == "stale"
    db.close()

    # Bundles are root-only evidence: the agent must not rewrite its inputs.
    hard = tmp / "hard"
    hard.mkdir(mode=0o775)
    (hard / "diff.patch").write_text("x\n")
    os.chmod(hard / "diff.patch", 0o664)
    collect.harden_bundle(hard)
    assert hard.stat().st_mode & 0o022 == 0
    assert (hard / "diff.patch").stat().st_mode & 0o022 == 0

    # Migration imports published heads and only requested heads with a bundle.
    state_path = tmp / "state.json"
    state_path.write_text(
        json.dumps(
            {
                "prs": {
                    "ErikBPF/aster#5": {"posted_head": "1" * 40},
                    "ErikBPF/aster#6": {"requested_head": "2" * 40},
                    "ErikBPF/aster#7": {"requested_head": "3" * 40},
                }
            }
        )
    )
    existing = review_in / f"ErikBPF__aster__6__{'2' * 12}"
    existing.mkdir()
    (existing / ".ready").write_text("now\n")
    migrated_db = ledger.connect(tmp / "migrated.db")
    assert collect.migrate_state(migrated_db, state_path, review_in) == 2
    assert ledger.get(migrated_db, "ErikBPF/aster", 5, "1" * 40)["state"] == "published"
    assert ledger.get(migrated_db, "ErikBPF/aster", 6, "2" * 40)["state"] == "queued"
    assert ledger.get(migrated_db, "ErikBPF/aster", 7, "3" * 40) is None
    marker_dir = tmp / "markers"
    ledger.record(migrated_db, "ErikBPF/aster", 8, "8" * 40, "", "forged")
    ledger.finish(migrated_db, "ErikBPF/aster", 8, "8" * 40, "published")
    assert collect.backfill_markers(migrated_db, marker_dir, state_path) == 1
    assert collect.backfill_markers(migrated_db, marker_dir, state_path) == 0
    assert (marker_dir / f"{'1' * 40}.json").exists()
    assert (marker_dir / f"{'1' * 40}.json").stat().st_mode & 0o077 == 0
    assert not (marker_dir / f"{'8' * 40}.json").exists()
    assert collect.marker_matches(marker_dir, "1" * 40)
    (marker_dir / "spoofed.json").write_text(json.dumps({"head": "0" * 40}))
    assert not collect.marker_matches(marker_dir, "spoofed")
    (marker_dir / "legacy.json").write_text(json.dumps({"head": "9" * 40}))
    assert collect.migrate_markers(marker_dir) == 2
    assert collect.marker_matches(marker_dir, "9" * 40)
    assert not (marker_dir / "legacy.json").exists()
    migrated_db.close()

    # Cross-PR background is scoped to the same repository, never another one.
    done = tmp / "review-done"
    done.mkdir()

    def write_review(name, repo, pr, summary):
        (done / name).write_text(
            json.dumps(
                {
                    "repo": repo,
                    "pr": pr,
                    "head": "a" * 40,
                    "summary": summary,
                    "findings": [
                        {"severity": "P2", "file": "x.rs", "line": 1, "title": "t"}
                    ],
                }
            )
        )

    write_review("ErikBPF__aster__1__aaaaaaaaaaaa.json", "ErikBPF/aster", 1, "aster earlier")
    write_review("ErikBPF__desktop-nixos__7__aaaaaaaaaaaa.json", "ErikBPF/desktop-nixos", 7, "desktop secret")
    write_review("ErikBPF__aster__2__aaaaaaaaaaaa.json", "ErikBPF/aster", 2, "aster current")
    ctx = collect.repo_context(tmp, "ErikBPF/aster", 2)
    assert "aster earlier" in ctx
    assert "PR #1" in ctx
    assert "desktop secret" not in ctx
    assert "PR #2" not in ctx, "the PR under review must not come from history"
    empty = collect.repo_context(tmp, "ErikBPF/servarr", 1)
    assert "No earlier published review" in empty

    config_path = tmp / "repos.json"
    config_path.write_text(
        json.dumps(
            {
                "repos": [
                    {
                        "repo": "ErikBPF/aster",
                        "bot_login": "hermes-pr-reviewer[bot]",
                    }
                ]
            }
        )
    )
    entries = tokens.load_config(str(config_path))
    assert entries[0]["credential"] == "app"
    assert "author" not in entries[0]
    assert entries[0]["ignore_authors"] == []
    assert entries[0]["ignore_labels"] == []
    assert entries[0]["ignore_title"] == ""
    settings = tokens.load_settings(str(config_path))
    assert settings.get("review_drafts", True) is True

    os.environ["GH_REVIEW_UPSTREAM_TOKEN"] = "test-token"
    assert (
        tokens.token_for({"credential": "upstream"}, "", "")
        == "test-token"
    )
    del os.environ["GH_REVIEW_UPSTREAM_TOKEN"]

    bad_config = tmp / "bad.json"
    bad_config.write_text(json.dumps({"repos": [{"repo": "ErikBPF/aster"}]}))
    try:
        tokens.load_config(str(bad_config))
    except ValueError:
        pass
    else:
        raise AssertionError("missing bot_login must be rejected")

    # Gate publishing: verdict drives the check run and the review.
    head = "c" * 40
    captured = []
    pub.gh_json = lambda args, token: (
        {"check_runs": [{"id": 9, "name": pub.CHECK_NAME, "conclusion": "success"}]}
        if "check-runs" in args[1]
        else []
    )
    pub.gh_api = lambda method, endpoint, token, payload: captured.append(
        (method, endpoint, payload)
    ) or {}
    assert pub.publish_check("ErikBPF/aster", head, [], "token", False) == "UNCHANGED"
    assert (
        pub.publish_check(
            "ErikBPF/aster", head, review()["findings"][:1], "token", False
        )
        == "UPDATED"
    )
    assert captured[-1][0] == "PATCH"
    assert captured[-1][2]["conclusion"] == "failure"

    captured.clear()
    assert (
        pub.publish_review(
            "ErikBPF/aster", 1, head, [], "hackerman-cr[bot]", "token", False
        )
        == "POSTED"
    )
    assert captured[0][2]["event"] == "APPROVE"
    assert captured[0][2]["commit_id"] == head

    captured.clear()
    assert (
        pub.publish_review(
            "ErikBPF/aster",
            1,
            head,
            review()["findings"][:1],
            "hackerman-cr[bot]",
            "token",
            False,
        )
        == "POSTED"
    )
    assert captured[0][2]["event"] == "REQUEST_CHANGES"

    captured.clear()
    pub.gh_json = lambda args, token: [
        {"user": {"login": "hackerman-cr[bot]"}, "commit_id": head, "state": "APPROVED"}
    ]
    assert (
        pub.publish_review(
            "ErikBPF/aster", 1, head, [], "hackerman-cr[bot]", "token", False
        )
        == "UNCHANGED"
    )
    assert not captured

    pub.gh_json = lambda args, token: {"check_runs": []}
    assert pub.publish_check("ErikBPF/aster", head, [], "token", False) == "CREATED"
    assert captured[-1][2]["head_sha"] == head
    assert captured[-1][2]["name"] == pub.CHECK_NAME

    marker_state = tmp / "state"
    pub.write_marker(marker_state, review()["head"], review(), "https://example.test")
    marker = json.loads(
        (marker_state / "published" / f"{review()['head']}.json").read_text()
    )
    assert marker["head"] == review()["head"] and marker["url"] == "https://example.test"
    assert (marker_state / "published").stat().st_mode & 0o077 == 0
    assert (marker_state / "published" / f"{review()['head']}.json").stat().st_mode & 0o077 == 0

    payload = gate.ruleset_payload(1)
    checks = payload["rules"][1]["parameters"]["required_status_checks"]
    assert checks[0]["context"] == "hackerman-cr/evaluation"
    assert checks[0]["integration_id"] == 5434668
    assert (
        payload["rules"][1]["parameters"]["strict_required_status_checks_policy"]
        is False
    )
    assert payload["rules"][0]["parameters"]["required_approving_review_count"] == 1
    assert payload["bypass_actors"] == [
        {"actor_id": 26701869, "actor_type": "User", "bypass_mode": "pull_request"}
    ]
    assert (
        gate.ruleset_payload(0)["rules"][0]["parameters"][
            "required_approving_review_count"
        ]
        == 0
    )

    # Trigger filters: author and label match case-insensitively; a title is a
    # regex; a broken regex fails open and never blocks a review.
    entry = {"repo": "ErikBPF/aster", "ignore_authors": ["Dependabot[BOT]"]}
    bot = {"author": {"login": "dependabot[bot]"}, "title": "chore: bump"}
    assert collect.ignore_reason(entry, bot) == "author dependabot[bot]"
    assert collect.ignore_reason({"repo": "ErikBPF/aster"}, bot) is None
    assert (
        collect.ignore_reason(
            {"repo": "ErikBPF/aster", "ignore_labels": ["skip-review"]},
            {"author": {"login": "erik"}, "labels": [{"name": "Skip-Review"}]},
        )
        == "label skip-review"
    )
    assert "title matches" in collect.ignore_reason(
        {"repo": "ErikBPF/aster", "ignore_title": "^chore"},
        {"author": {"login": "erik"}, "title": "chore: bump"},
    )
    assert (
        collect.ignore_reason(
            {"repo": "ErikBPF/aster", "ignore_title": "("},
            {"author": {"login": "erik"}, "title": "anything"},
        )
        is None
    ), "an invalid pattern must fail open"

    # Reused verdicts keep the findings and record why no model ran.
    reused = collect.reuse_review(review(), "d" * 40, "b" * 40)
    assert reused["head"] == "d" * 40 and reused["base"] == "b" * 40
    assert reused["findings"] == review()["findings"]
    assert any("without a new model run" in item for item in reused["limits"])
    assert review()["head"] == "a" * 40, "the published packet must not be mutated"

    # Ledger: a legacy table gains diff_hash; reusing is terminal for workers
    # but not for the publisher.
    legacy_path = tmp / "legacy.db"
    legacy = sqlite3.connect(legacy_path)
    legacy.execute(
        """
        CREATE TABLE reviews (
            repo TEXT NOT NULL, pr INTEGER NOT NULL, head TEXT NOT NULL,
            base TEXT NOT NULL DEFAULT '', bundle TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT 'queued',
            attempts INTEGER NOT NULL DEFAULT 0,
            lease_owner TEXT, lease_expires REAL,
            requested_at REAL NOT NULL, updated_at REAL NOT NULL, error TEXT,
            PRIMARY KEY (repo, pr, head)
        )
        """
    )
    legacy.commit()
    legacy.close()
    upgrade = ledger.connect(legacy_path)
    columns = {row["name"] for row in upgrade.execute("PRAGMA table_info(reviews)")}
    assert "diff_hash" in columns
    upgrade.close()

    reuse_db = ledger.connect(tmp / "reuse.db")
    ledger.mark_reusing(
        reuse_db, "ErikBPF/aster", 30, "f" * 40, "b" * 40, "reuse-bundle", "g" * 64
    )
    row = ledger.get(reuse_db, "ErikBPF/aster", 30, "f" * 40)
    assert row["state"] == "reusing", dict(row)
    assert ledger.claimable_count(reuse_db) == 0
    assert ledger.claim(reuse_db, "worker", 60) is None
    ledger.record(reuse_db, "ErikBPF/aster", 31, "e" * 40, "b" * 40, "old", "h" * 64)
    ledger.finish(reuse_db, "ErikBPF/aster", 31, "e" * 40, "published")
    assert ledger.last_published(reuse_db, "ErikBPF/aster", 31)["diff_hash"] == "h" * 64
    ledger.requeue(reuse_db, "ErikBPF/aster", 30, "f" * 40)
    assert ledger.get(reuse_db, "ErikBPF/aster", 30, "f" * 40)["state"] == "queued"

    # A live worker owns its head; reuse must not overwrite the lease.
    ledger.record(reuse_db, "ErikBPF/aster", 32, "b" * 40, "", "leased")
    reuse_db.execute(
        "UPDATE reviews SET state = 'leased', lease_expires = ? WHERE pr = 32",
        (time.time() + 600,),
    )
    ledger.mark_reusing(
        reuse_db, "ErikBPF/aster", 32, "b" * 40, "", "leased", "j" * 64
    )
    assert ledger.get(reuse_db, "ErikBPF/aster", 32, "b" * 40)["state"] == "leased"
    reuse_db.close()

    # Reuse path: a copied packet, a minimal evidence bundle, and a row no
    # worker can claim.
    args = type("Args", (), {"data_dir": str(tmp / "reuse-data")})
    data = Path(args.data_dir)
    (data / "review-done" / "old-packet").mkdir(parents=True)
    (data / "review-done" / "old-packet" / "diff.patch").write_text(
        "diff --git a/x b/x\n+let value = 1;\n"
    )
    (data / "review-done" / "old-packet" / "docs").mkdir()
    (data / "review-done" / "old-packet" / "docs" / "AGENTS.md").write_text(
        "quote from repo guidance\n"
    )
    (data / "review-done" / "old-packet" / ".ready").write_text("old\n")
    (data / "review-done" / "old-packet.json").write_text(json.dumps(review()))
    reuse_db = ledger.connect(tmp / "reuse-write.db")
    previous = {"bundle": "old-packet", "head": "a" * 40}

    # Guidance is refetched at the new base and compared, so the test stands in
    # for the GitHub calls.
    original_docs, original_skills = collect.fetch_docs, collect.fetch_skills

    def same_docs(repo, base, dest, token):
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "AGENTS.md").write_text("quote from repo guidance\n")
        return 1

    collect.fetch_docs = same_docs
    collect.fetch_skills = lambda repo, base, dest, token: 0

    result = collect.reuse_bundle(
        args,
        reuse_db,
        "ErikBPF/aster",
        1,
        "f" * 40,
        "b" * 40,
        "new-bundle",
        "i" * 64,
        previous,
        "token",
    )
    assert result == data / "review-in" / "new-bundle"
    assert (result / ".reuse").exists()
    assert not (result / ".ready").exists(), "a reuse bundle must not look claimable"
    assert (result / "diff.patch").read_text().startswith("diff --git")
    assert (result / "docs" / "AGENTS.md").read_text().startswith("quote"), (
        "docs must be copied so documented evidence survives strict publication"
    )
    packet = json.loads((data / "review-out" / "new-bundle.json").read_text())
    assert packet["head"] == "f" * 40 and packet["base"] == "b" * 40
    row = ledger.get(reuse_db, "ErikBPF/aster", 1, "f" * 40)
    assert row["state"] == "reusing" and row["diff_hash"] == "i" * 64
    assert "reused from" in (result / "request.md").read_text()

    # Guidance changed at the new base: the old verdict is not safe to reuse.
    def changed_docs(repo, base, dest, token):
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "AGENTS.md").write_text("changed rule\n")
        return 1

    collect.fetch_docs = changed_docs
    assert (
        collect.reuse_bundle(
            args,
            reuse_db,
            "ErikBPF/aster",
            1,
            "d" * 40,
            "c" * 40,
            "changed-bundle",
            "l" * 64,
            previous,
            "token",
        )
        is None
    )
    assert not (data / "review-in" / "changed-bundle").exists()
    assert not (data / "review-out" / "changed-bundle.json").exists()
    collect.fetch_docs, collect.fetch_skills = original_docs, original_skills
    reuse_db.close()

    # On-demand request: a published head is requeued and its old payload is
    # discarded; an in-flight head is left alone.
    req_data = tmp / "request-data"
    req_state = tmp / "request-state"
    (req_data / "review-in" / "bundle").mkdir(parents=True)
    (req_data / "review-out").mkdir(parents=True)
    (req_data / "review-out" / "bundle.json").write_text("{}\n")
    (req_state / "published").mkdir(parents=True)
    marker_path = req_state / "published" / f"{'a' * 40}.json"
    marker_path.write_text(json.dumps({"head": "a" * 40}))
    req_db_path = tmp / "request.db"
    req_db = ledger.connect(req_db_path)
    ledger.record(req_db, "ErikBPF/aster", 40, "a" * 40, "b" * 40, "bundle")
    ledger.finish(req_db, "ErikBPF/aster", 40, "a" * 40, "published")
    req_db.close()

    def request(*extra):
        return subprocess.run(
            [
                sys.executable,
                str(REQUEST),
                "--ledger",
                str(req_db_path),
                "--data-dir",
                str(req_data),
                "--state-dir",
                str(req_state),
                "--repo",
                "ErikBPF/aster",
                "--pr",
                "40",
                *extra,
            ],
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

    assert request("--head", "a" * 40).startswith("REQUEUED")
    assert not (req_data / "review-in" / "bundle").exists()
    assert not (req_data / "review-out" / "bundle.json").exists()
    assert not marker_path.exists(), "a stale marker would satisfy the wait loop"
    req_db = ledger.connect(req_db_path)
    assert ledger.get(req_db, "ErikBPF/aster", 40, "a" * 40)["state"] == "queued"
    req_db.close()
    assert request("--head", "a" * 40).startswith("ALREADY queued")
    assert request("--head", "9" * 40).startswith("NO-REVIEW")

# Review isolation invariants: a fresh session per run, no cross-PR recall,
# and no stale pre-parallel job left behind.
bootstrap = (SCRIPTS / "bootstrap-cron.sh").read_text()
# cron create has no --no-continuity flag; continuity is off by default there
# and the edit path enforces it for pre-existing workers.
assert bootstrap.count("--no-continuity") == 1, "only edit may pass --no-continuity"
create_call = bootstrap.split("cron create", 1)[1].split("done", 1)[0]
assert "--no-continuity" not in create_call
assert "Retire workers above the configured parallelism" in bootstrap
assert "refusing to mutate jobs" in bootstrap, "failed cron list must not create workers"
module = (ROOT / "modules/hosts/discovery/hermes-pr-review.nix").read_text()
assert "pkgs.gawk" in module, "bootstrap parses cron list with awk; it must ship"
assert "ledgerDir" in module, "reviews are leased in the ledger"
assert 'ExecStartPost = "${dispatch}' in module, "new bundles dispatch workers immediately"
assert "review-claims" not in module, "file claims are replaced by ledger leases"
assert 'collectInterval = lib.mkOption {' in module and 'default = "2min";' in module
assert 'max="$PARALLELISM"' in bootstrap
assert "--script pr-review-claim.py" in bootstrap
assert 'rm -f "$DATA_DIR/scripts/pr-review-ready.py"' in bootstrap
assert 'if [ -n "$old_id" ]; then' in bootstrap, "legacy job must be retired unconditionally"

agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
assert 'agent.disabled_toolsets = ["memory" "session_search"];' in agents
assert "memory_enabled = false;" in agents
assert "user_profile_enabled = false;" in agents

# Claim worker contract: an idle worker must emit the Hermes wake gate, and a
# worker that claimed an older head must skip it when a newer head is live.
claim_script = SCRIPTS / "claim.py"


def run_claim(ledger_path, review_in):
    env = dict(os.environ)
    env["HERMES_REVIEW_LEDGER"] = str(ledger_path)
    env["HERMES_REVIEW_IN"] = str(review_in)
    proc = subprocess.run(
        [sys.executable, str(claim_script)],
        capture_output=True,
        text=True,
        env=env,
        check=True,
    )
    return [line for line in proc.stdout.splitlines() if line.strip()]


with tempfile.TemporaryDirectory() as raw:
    tmp = Path(raw)
    review_in = tmp / "review-in"
    review_in.mkdir()
    db_path = tmp / "ledger.db"

    idle = run_claim(db_path, review_in)
    assert idle[-2:] == ["NO_CLAIM", '{"wakeAgent": false}'], idle

    old_head, new_head = "a" * 40, "c" * 40
    db = ledger.connect(db_path)
    ledger.record(db, "owner/repo", 1, old_head, "b" * 40, "old-bundle")
    ledger.record(db, "owner/repo", 1, new_head, "b" * 40, "new-bundle")
    db.execute("UPDATE reviews SET requested_at = 1000 WHERE head = ?", (old_head,))
    db.execute("UPDATE reviews SET requested_at = 2000 WHERE head = ?", (new_head,))
    db.commit()
    db.close()
    for bundle in ("old-bundle", "new-bundle"):
        (review_in / bundle).mkdir()
        (review_in / bundle / ".ready").write_text("ready\n")

    claimed = run_claim(db_path, review_in)
    assert claimed == ["CLAIM new-bundle"], claimed
    db = ledger.connect(db_path)
    old = ledger.get(db, "owner/repo", 1, old_head)
    new = ledger.get(db, "owner/repo", 1, new_head)
    assert old["state"] == "stale" and old["error"] == "superseded before review", dict(old)
    assert new["state"] == "leased", dict(new)
    db.close()

    # A revived current head must outrank a published newer head; otherwise
    # collect's requeue + claim cycle livelocks after a force-push back.
    db = ledger.connect(db_path)
    ledger.finish(db, "owner/repo", 1, new_head, "published")
    ledger.requeue(db, "owner/repo", 1, old_head)
    revived = ledger.get(db, "owner/repo", 1, old_head)
    assert revived["state"] == "queued", dict(revived)
    db.close()

    claimed = run_claim(db_path, review_in)
    assert claimed == ["CLAIM old-bundle"], claimed

print("pr-review-publish: ok")
