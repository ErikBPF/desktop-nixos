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
READY = SCRIPTS / "ready.py"
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

    review_in = tmp / "in"
    review_out = tmp / "out"
    review_in.mkdir()
    review_out.mkdir()
    ready_bundle = review_in / "one"
    ready_bundle.mkdir()
    env = dict(os.environ, HERMES_REVIEW_IN=str(review_in), HERMES_REVIEW_OUT=str(review_out))
    denied = subprocess.run(
        [str(READY)], env=env, text=True, capture_output=True, check=True
    ).stdout.strip()
    assert denied == "NO_READY", denied
    (ready_bundle / ".ready").write_text("now\n")
    allowed = subprocess.run(
        [str(READY)], env=env, text=True, capture_output=True, check=True
    ).stdout.strip()
    assert allowed == "READY one", allowed
    (ready_bundle / ".posted").write_text("posted\n")
    posted = subprocess.run(
        [str(READY)], env=env, text=True, capture_output=True, check=True
    ).stdout.strip()
    assert posted == "NO_READY", posted

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

print("pr-review-publish: ok")
