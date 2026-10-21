#!/usr/bin/env python3
"""Contract check for the PR review publisher and ready probe.

Synthetic only. No GitHub calls, tokens, or host state.
"""

import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBLISH = ROOT / "scripts/pr-review/publish.py"
READY = ROOT / "scripts/pr-review/ready.py"


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
    body = pub.render(parsed)
    assert body.startswith("## Automated Comet review"), body[:60]
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
    assert "No new P1/P2 findings" in pub.render(parsed)

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

print("pr-review-publish: ok")
