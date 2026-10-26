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
sys.path.insert(0, str(SCRIPTS))

import tokens  # noqa: E402


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pub = load(PUBLISH, "pr_review_publish")


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
    assert "does not approve or request changes" in body

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

    review_in = tmp / "in"
    review_out = tmp / "out"
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
    assert claim() == "CLAIM newer", "a fresh claim must not be stolen"
    assert claim() == "NO_CLAIM", "each worker gets a distinct bundle"

    # A claimed bundle whose review already landed is not re-issued.
    (older / ".claim").unlink()
    (review_out / "older.json").write_text("{}")
    assert claim() == "NO_CLAIM"

    # An abandoned claim is reclaimable after the TTL.
    (review_out / "older.json").unlink()
    (older / ".ready").unlink()
    (newer / ".claim").unlink()
    (newer / ".claim").write_text("dead worker\n")
    os.utime(newer / ".claim", (0, 0))
    assert claim("--claim-ttl", "1") == "CLAIM newer"
    (newer / ".posted").write_text("posted\n")
    (newer / ".claim").unlink()
    assert claim() == "NO_CLAIM"

    # Publishing releases the claim marker.
    (newer / ".claim").write_text("w1\n")
    pub.mark_bundle(newer, "posted")
    assert not (newer / ".claim").exists()

    # Superseded and closed-PR bundles are pruned; a fresh claim is preserved.
    collect = load(SCRIPTS / "collect.py", "pr_review_collect")
    keep = review_in / "ErikBPF__aster__1__aaaaaaaaaaaa"
    superseded = review_in / "ErikBPF__aster__1__bbbbbbbbbbbb"
    closed = review_in / "ErikBPF__aster__2__cccccccccccc"
    busy = review_in / "ErikBPF__aster__1__dddddddddddd"
    for bundle in (keep, superseded, closed, busy):
        bundle.mkdir()
    (busy / ".claim").write_text("w2\n")
    removed = collect.prune_repo_bundles(
        review_in, "ErikBPF/aster", {1: "a" * 40}, 3600
    )
    assert removed == 2, removed
    assert keep.exists() and busy.exists()
    assert not superseded.exists() and not closed.exists()

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
    assert entries[0]["author"] == "ErikBPF"

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

# Review isolation invariants: a fresh session per run, and no cross-PR recall.
bootstrap = (SCRIPTS / "bootstrap-cron.sh").read_text()
assert bootstrap.count("--no-continuity") == 2, "create and edit must disable continuity"
assert "--script pr-review-claim.py" in bootstrap

agents = (ROOT / "modules/hosts/discovery/hermes-agents.nix").read_text()
assert 'agent.disabled_toolsets = ["memory" "session_search"];' in agents
assert "memory_enabled = false;" in agents
assert "user_profile_enabled = false;" in agents

print("pr-review-publish: ok")
