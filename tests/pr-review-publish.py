#!/usr/bin/env python3
"""Contract check for the PR review publisher and ready probe.

Synthetic only. No GitHub calls, tokens, or host state.
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts/pr-review"
PUBLISH = SCRIPTS / "publish.py"
GATE = SCRIPTS / "apply-gate.py"
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
        return result.stdout.strip()

    older = review_in / "older"
    newer = review_in / "newer"
    for bundle, mtime in ((older, 1_000_000), (newer, 2_000_000)):
        bundle.mkdir()
        (bundle / ".ready").write_text("now\n")
        os.utime(bundle, (mtime, mtime))
    ledger.record(db, "ErikBPF/aster", 1, "a" * 40, "", "older")
    ledger.record(db, "ErikBPF/aster", 1, "b" * 40, "", "newer")

    assert claim() == "CLAIM older", "oldest head must lease first"
    assert claim() == "CLAIM newer", "a fresh lease must not be stolen"
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
    assert missing.stdout.strip() == "NO_CLAIM"

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

    # A failed head whose PR merged or closed becomes stale, not retried.
    ledger.record(db, "ErikBPF/aster", 99, "f" * 40, "", "gone")
    ledger.finish(db, "ErikBPF/aster", 99, "f" * 40, "failed", "bundle missing")
    assert collect.reconcile_closed(db, "ErikBPF/aster", {1, 2, 3, 4}) == 1
    row = db.execute("SELECT state FROM reviews WHERE pr = 99").fetchone()
    assert row["state"] == "stale"
    db.close()

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
    assert (marker_dir / "ErikBPF__aster__5__111111111111.json").exists()
    assert not (marker_dir / "forged.json").exists()
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
    pub.write_marker(marker_state, "bundle", review(), "https://example.test")
    marker = json.loads((marker_state / "published" / "bundle.json").read_text())
    assert marker["head"] == review()["head"] and marker["url"] == "https://example.test"

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

print("pr-review-publish: ok")
