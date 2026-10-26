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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts/pr-review"
PUBLISH = SCRIPTS / "publish.py"
GATE = SCRIPTS / "apply-gate.py"
sys.path.insert(0, str(SCRIPTS))

import tokens  # noqa: E402


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

    # Claims live outside the root-owned inbox: the agent must be able to
    # write them without owning review-in.
    review_in = tmp / "in"
    review_out = tmp / "out"
    claims = tmp / "claims"
    review_in.mkdir()
    review_out.mkdir()
    claim_script = SCRIPTS / "claim.py"

    def claim(*extra):
        result = subprocess.run(
            [str(claim_script), "--worker", "w1", *extra],
            env=dict(
                os.environ,
                HERMES_REVIEW_IN=str(review_in),
                HERMES_REVIEW_OUT=str(review_out),
                HERMES_REVIEW_CLAIMS=str(claims),
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
        os.utime(bundle, (mtime, mtime))

    assert claim() == "NO_CLAIM", "a bundle without .ready is not reviewable"
    (older / ".ready").write_text("now\n")
    (newer / ".ready").write_text("now\n")
    assert claim() == "CLAIM older", "oldest bundle must claim first"
    assert not (review_in / ".claim.lock").exists(), "lock must not be in review-in"
    assert (claims / "older.claim").exists(), "claim must be in the claims dir"
    assert claim() == "CLAIM newer", "a fresh claim must not be stolen"
    assert claim() == "NO_CLAIM", "each worker gets a distinct bundle"

    (review_out / "older.json").write_text("{}")
    assert claim() == "NO_CLAIM"

    (review_out / "older.json").unlink()
    (older / ".ready").unlink()
    (claims / "newer.claim").unlink()
    (claims / "newer.claim").write_text("dead worker\n")
    os.utime(claims / "newer.claim", (0, 0))
    assert claim("--claim-ttl", "1") == "CLAIM newer"
    (newer / ".posted").write_text("posted\n")
    (claims / "newer.claim").unlink()
    assert claim() == "NO_CLAIM"

    # Publishing releases the claim marker.
    (claims / "newer.claim").write_text("w1\n")
    pub.mark_bundle(newer, "posted", claims)
    assert not (claims / "newer.claim").exists()

    # Superseded and closed-PR bundles are pruned; a fresh claim is preserved.
    collect = load(SCRIPTS / "collect.py", "pr_review_collect")
    keep = review_in / "ErikBPF__aster__1__aaaaaaaaaaaa"
    superseded = review_in / "ErikBPF__aster__1__bbbbbbbbbbbb"
    closed = review_in / "ErikBPF__aster__2__cccccccccccc"
    busy = review_in / "ErikBPF__aster__1__dddddddddddd"
    for bundle in (keep, superseded, closed, busy):
        bundle.mkdir()
    (claims / f"{busy.name}.claim").write_text("w2\n")
    removed = collect.prune_repo_bundles(
        review_in, claims, "ErikBPF/aster", {1: "a" * 40}, 3600
    )
    assert removed == 2, removed
    assert keep.exists() and busy.exists()
    assert not superseded.exists() and not closed.exists()

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

    write_review("x1.json", "ErikBPF/aster", 1, "aster earlier")
    write_review("y1.json", "ErikBPF/desktop-nixos", 7, "desktop secret")
    write_review("x2.json", "ErikBPF/aster", 2, "aster current")
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

    payload = gate.ruleset_payload(1)
    checks = payload["rules"][1]["parameters"]["required_status_checks"]
    assert checks[0]["context"] == "hackerman-cr/evaluation"
    assert checks[0]["integration_id"] == 5434668
    assert payload["rules"][0]["parameters"]["required_approving_review_count"] == 1
    assert payload["bypass_actors"] == []
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
assert 'max="$PARALLELISM"' in bootstrap
assert "--script pr-review-claim.py" in bootstrap
assert 'rm -f "$DATA_DIR/scripts/pr-review-ready.py"' in bootstrap
assert 'if [ -n "$old_id" ]; then' in bootstrap, "legacy job must be retired unconditionally"

agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
assert 'agent.disabled_toolsets = ["memory" "session_search"];' in agents
assert "memory_enabled = false;" in agents
assert "user_profile_enabled = false;" in agents

print("pr-review-publish: ok")
