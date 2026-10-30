#!/usr/bin/env python3
"""Publish Hermes cr-pr review bundles as a gate check, a review, and a comment.

The posting credential lives only in this host process. Hackerman writes JSON
and never sees it. A clean packet submits APPROVE and a successful check run; a
packet with findings submits REQUEST_CHANGES and a failing check run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import ledger
import tokens

GH = "gh"
MARKER = "<!-- hermes-pr-review:"
CHECK_NAME = "hackerman-cr/evaluation"
MAX_FINDINGS = 5
MAX_BODY = 60_000
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def gh_json(args: list[str], token: str) -> object:
    proc = subprocess.run(
        [GH, *args], capture_output=True, text=True, env=tokens.gh_env(token)
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"gh {' '.join(args)} failed ({proc.returncode}): {proc.stderr.strip()}"
        )
    return json.loads(proc.stdout)


def gh_api(method: str, endpoint: str, token: str, payload: dict) -> object:
    proc = subprocess.run(
        [GH, "api", "--method", method, endpoint, "--input", "-"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=tokens.gh_env(token),
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"gh api {method} {endpoint} failed ({proc.returncode}): "
            f"{proc.stderr.strip()}"
        )
    return json.loads(proc.stdout)


def verdict(findings: list[dict]) -> str:
    return "failure" if findings else "success"


def review_event(findings: list[dict]) -> str:
    return "REQUEST_CHANGES" if findings else "APPROVE"


def clean(value: object, limit: int = 4000) -> str:
    text = str(value or "")
    text = CONTROL.sub("", text)
    text = HTML_COMMENT.sub("", text)
    text = text.replace("\r\n", "\n").strip()
    if len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return text


def validate(review: dict) -> tuple[dict, list[str]]:
    errors: list[str] = []
    repo = review.get("repo")
    pr = review.get("pr")
    head = review.get("head")
    if not isinstance(repo, str) or "/" not in repo:
        errors.append("repo must be owner/name")
    if not isinstance(pr, int) or pr <= 0:
        errors.append("pr must be a positive integer")
    if not isinstance(head, str) or not re.fullmatch(r"[0-9a-f]{7,40}", head):
        errors.append("head must be a commit SHA")
    findings = review.get("findings")
    if not isinstance(findings, list):
        errors.append("findings must be a list")
        findings = []
    accepted = []
    for index, finding in enumerate(findings):
        if not isinstance(finding, dict):
            errors.append(f"finding {index} is not an object")
            continue
        severity = finding.get("severity")
        if severity not in ("P1", "P2"):
            errors.append(f"finding {index}: severity must be P1 or P2")
            continue
        file = clean(finding.get("file"), 500)
        line = finding.get("line")
        title = clean(finding.get("title"), 300)
        body = clean(finding.get("body"), 4000)
        evidence = clean(finding.get("evidence"), 2000)
        action = clean(finding.get("action"), 2000)
        if not file or not title or not body or not evidence or not action:
            errors.append(f"finding {index}: missing required field")
            continue
        if isinstance(line, str) and line.isdigit():
            line = int(line)
        if not isinstance(line, int) or line <= 0:
            errors.append(f"finding {index}: line must be positive")
            continue
        finding = dict(finding)
        finding.update(
            {
                "file": file,
                "line": line,
                "title": title,
                "body": body,
                "evidence": evidence,
                "action": action,
            }
        )
        accepted.append(finding)
    review = dict(review)
    review["findings"] = accepted
    return review, errors


def evidence_in_bundle(evidence: str, bundle: Path) -> bool:
    needle = evidence.strip().strip("`").strip()
    if len(needle) < 8:
        return False
    candidates = [bundle / "diff.patch"]
    for directory in ("docs", "skills"):
        root = bundle / directory
        if root.exists():
            candidates.extend(path for path in root.rglob("*") if path.is_file())
    for path in candidates:
        try:
            if needle in path.read_text(errors="ignore"):
                return True
        except OSError:
            continue
    return False


def render(review: dict, repo: str, limit: int = MAX_FINDINGS) -> str:
    findings = sorted(
        review["findings"], key=lambda item: (item["severity"] != "P1",)
    )
    shown = findings[:limit]
    head = review["head"]
    short = head[:7]
    routed = [clean(item, 100) for item in review.get("routed_skills", [])]
    lines = [
        f"## Automated review — `{repo}` — `{short}`",
        "",
        f"Reviewed `{head}` against `{clean(review.get('base'), 40)}`.",
    ]
    if routed:
        lines.append("Routed: " + ", ".join(f"`{item}`" for item in routed) + ".")
    summary = clean(review.get("summary"), 2000)
    if summary:
        lines.extend(["", summary])
    if not shown:
        lines.extend(
            ["", "No new P1/P2 findings at this head. No action requested."]
        )
    for finding in shown:
        lines.extend(
            [
                "",
                f"### {finding['severity']} — `{finding['file']}:{finding['line']}` — {finding['title']}",
                "",
                finding["body"],
                "",
                "**Evidence**",
                "",
                "> " + finding["evidence"].replace("\n", "\n> "),
                "",
                f"**Action:** {finding['action']}",
            ]
        )
    if len(findings) > limit:
        lines.extend(
            [
                "",
                f"{len(findings) - limit} further finding(s) omitted from this comment.",
            ]
        )
    validation = [
        clean(item, 500) for item in review.get("validation", []) if clean(item, 500)
    ]
    limits = [clean(item, 500) for item in review.get("limits", []) if clean(item, 500)]
    if validation or limits:
        lines.extend(["", "---", "", "**Validation**"])
        lines.extend(f"- {item}" for item in validation)
        if limits:
            lines.extend(["", "**Limits**"])
            lines.extend(f"- {item}" for item in limits)
    digest = hashlib.sha256(
        json.dumps(
            {"head": head, "findings": shown, "summary": summary},
            sort_keys=True,
        ).encode()
    ).hexdigest()[:16]
    lines.extend(
        [
            "",
            "<sub>Automated review. Findings are candidates for human confirmation. "
            "Hackerman approves only when it found no P1/P2 issues; it does not "
            "replace human review of design or intent.</sub>",
            f"{MARKER}{head}:{digest} -->",
        ]
    )
    body = "\n".join(lines).strip() + "\n"
    return body[:MAX_BODY]


def find_comment(repo: str, pr: int, bot_login: str, token: str) -> dict | None:
    pages = gh_json(
        [
            "api",
            "--paginate",
            "--slurp",
            f"repos/{repo}/issues/{pr}/comments?per_page=100",
        ],
        token,
    )
    comments = [item for page in pages for item in page]
    for comment in reversed(comments):
        body = comment.get("body") or ""
        if comment.get("user", {}).get("login") == bot_login and MARKER in body:
            return comment
    return None


def upsert_comment(
    repo: str, pr: int, body: str, bot_login: str, token: str, dry_run: bool
) -> str:
    if dry_run:
        print(body)
        return "DRY-RUN"
    existing = find_comment(repo, pr, bot_login, token)
    if existing:
        if (existing.get("body") or "").strip() == body.strip():
            return "UNCHANGED"
        proc = subprocess.run(
            [
                GH,
                "api",
                "--method",
                "PATCH",
                f"repos/{repo}/issues/comments/{existing['id']}",
                "--input",
                "-",
            ],
            input=json.dumps({"body": body}),
            check=True,
            capture_output=True,
            text=True,
            env=tokens.gh_env(token),
        )
        return json.loads(proc.stdout).get("html_url", "UPDATED")
    proc = subprocess.run(
        [
            GH,
            "api",
            "--method",
            "POST",
            f"repos/{repo}/issues/{pr}/comments",
            "--input",
            "-",
        ],
        input=json.dumps({"body": body}),
        check=True,
        capture_output=True,
        text=True,
        env=tokens.gh_env(token),
    )
    return json.loads(proc.stdout).get("html_url", "POSTED")


def publish_check(
    repo: str,
    head: str,
    findings: list[dict],
    token: str,
    dry_run: bool,
) -> str:
    conclusion = verdict(findings)
    short = head[:7]
    if findings:
        title = f"{len(findings)} P1/P2 finding(s)"
        summary = (
            f"Hackerman requested changes at `{short}`. "
            "See the review comment for evidence and required action."
        )
    else:
        title = "No P1/P2 findings"
        summary = f"Hackerman found no P1/P2 issues at `{short}`."
    payload = {
        "name": CHECK_NAME,
        "status": "completed",
        "conclusion": conclusion,
        "output": {"title": title, "summary": summary},
    }
    if dry_run:
        print(f"CHECK {repo}@{short} {conclusion} {title}")
        return "DRY-RUN"
    query = f"repos/{repo}/commits/{head}/check-runs?check_name={CHECK_NAME}&per_page=100"
    runs = gh_json(["api", query], token).get("check_runs", [])
    existing = next((run for run in runs if run.get("name") == CHECK_NAME), None)
    if existing and existing.get("conclusion") == conclusion:
        return "UNCHANGED"
    if existing:
        gh_api("PATCH", f"repos/{repo}/check-runs/{existing['id']}", token, payload)
        return "UPDATED"
    payload["head_sha"] = head
    gh_api("POST", f"repos/{repo}/check-runs", token, payload)
    return "CREATED"


def publish_review(
    repo: str,
    pr: int,
    head: str,
    findings: list[dict],
    bot_login: str,
    token: str,
    dry_run: bool,
) -> str:
    event = review_event(findings)
    wanted = "APPROVED" if event == "APPROVE" else "CHANGES_REQUESTED"
    short = head[:7]
    if findings:
        body = (
            f"Automated review at `{short}`: {len(findings)} P1/P2 finding(s). "
            "See the review comment for evidence and required action."
        )
    else:
        body = f"Automated review at `{short}`: no P1/P2 findings."
    body += "\n\n<!-- hermes-pr-review-gate -->"
    if dry_run:
        print(f"REVIEW {repo}#{pr}@{short} {event}")
        return "DRY-RUN"
    reviews = gh_json(["api", f"repos/{repo}/pulls/{pr}/reviews?per_page=100"], token)
    for review in reviews:
        if (
            review.get("user", {}).get("login") == bot_login
            and review.get("commit_id") == head
            and review.get("state") == wanted
        ):
            return "UNCHANGED"
    gh_api(
        "POST",
        f"repos/{repo}/pulls/{pr}/reviews",
        token,
        {"commit_id": head, "event": event, "body": body},
    )
    return "POSTED"


def current_head(repo: str, pr: int, token: str) -> tuple[str, str]:
    data = gh_json(
        ["pr", "view", str(pr), "--repo", repo, "--json", "headRefOid,state"], token
    )
    return data["headRefOid"], data["state"]


def mark_bundle(bundle: Path, outcome: str) -> None:
    (bundle / ".posted").write_text(f"{outcome} {now()}\n")
    ready = bundle / ".ready"
    if ready.exists():
        ready.unlink()


def write_marker(state_dir: Path, bundle: str, review: dict, url: str | None) -> None:
    """Record publication outside the agent-writable data mount."""
    published = state_dir / "published"
    published.mkdir(parents=True, exist_ok=True)
    (published / f"{bundle}.json").write_text(
        json.dumps(
            {
                "repo": review["repo"],
                "pr": review["pr"],
                "head": review["head"],
                "url": url,
                "published_at": now(),
            },
            indent=2,
        )
        + "\n"
    )


def retire_bundle(bundle: Path, target: Path) -> None:
    """Move a finished bundle out of the inbox so it stops looking queued."""
    if not bundle.exists():
        return
    destination = target / bundle.name
    if destination.exists():
        shutil.rmtree(destination, ignore_errors=True)
    shutil.move(str(bundle), str(destination))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--state-dir", default="/var/lib/hermes-pr-review")
    parser.add_argument("--app-credential", required=True)
    parser.add_argument("--app-token-cache", required=True)
    parser.add_argument("--ledger", default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--post-empty", action="store_true")
    parser.add_argument("--no-strict-evidence", dest="strict_evidence", action="store_false")
    args = parser.parse_args()

    entries = {entry["repo"]: entry for entry in tokens.load_config(args.config)}
    ledger_path = args.ledger or str(
        Path(args.data_dir) / "review-ledger" / "ledger.db"
    )
    db = ledger.connect(ledger_path)
    out_dir = Path(args.data_dir) / "review-out"
    in_dir = Path(args.data_dir) / "review-in"
    done_dir = Path(args.data_dir) / "review-done"
    stale_dir = Path(args.data_dir) / "review-stale"
    for directory in (out_dir, done_dir, stale_dir):
        directory.mkdir(parents=True, exist_ok=True)

    published = 0
    for path in sorted(out_dir.glob("*.json")):
        try:
            review, errors = validate(json.loads(path.read_text()))
            if errors:
                print(f"INVALID {path.name}: {'; '.join(errors)}", file=sys.stderr)
                if not args.dry_run:
                    path.replace(stale_dir / path.name)
                    ledger.finish_bundle(
                        db, path.stem, "failed", "invalid review packet"
                    )
                continue
            repo, pr, head = review["repo"], review["pr"], review["head"]
            entry = entries.get(repo)
            if entry is None:
                print(f"REPO-NOT-CONFIGURED {path.name}", file=sys.stderr)
                if not args.dry_run:
                    path.replace(stale_dir / path.name)
                    ledger.finish_bundle(db, path.stem, "stale", "repo not configured")
                continue
            bundle = in_dir / path.stem
            if not bundle.exists():
                print(f"NO-BUNDLE {path.name}", file=sys.stderr)
                if not args.dry_run:
                    path.replace(stale_dir / path.name)
                    ledger.finish_bundle(db, path.stem, "failed", "bundle missing")
                continue
            token = tokens.token_for(
                entry, args.app_credential, args.app_token_cache
            )
            live_head, pr_state = current_head(repo, pr, token)
            if pr_state != "OPEN" or live_head != head:
                print(f"STALE {path.name}: {head} != {live_head}")
                if not args.dry_run:
                    path.replace(stale_dir / path.name)
                    ledger.finish(db, repo, pr, head, "stale", "head moved")
                    mark_bundle(bundle, "stale")
                    retire_bundle(bundle, stale_dir)
                continue
            if args.strict_evidence:
                kept = []
                for finding in review["findings"]:
                    if evidence_in_bundle(finding["evidence"], bundle):
                        kept.append(finding)
                    else:
                        print(
                            f"DROP {path.name} {finding['id']}: evidence not in bundle",
                            file=sys.stderr,
                        )
                review["findings"] = kept
            if not review["findings"] and not args.post_empty:
                if args.dry_run:
                    body = None
                    url = None
                else:
                    existing = find_comment(
                        repo, pr, entry["bot_login"], token
                    )
                    if existing:
                        body = render(review, repo)
                        url = upsert_comment(
                            repo,
                            pr,
                            body,
                            entry["bot_login"],
                            token,
                            False,
                        )
                    else:
                        body = None
                        url = None
            else:
                body = render(review, repo)
                url = upsert_comment(
                    repo,
                    pr,
                    body,
                    entry["bot_login"],
                    token,
                    args.dry_run,
                )
            if args.dry_run:
                publish_review(
                    repo,
                    pr,
                    head,
                    review["findings"],
                    entry["bot_login"],
                    token,
                    True,
                )
                publish_check(repo, head, review["findings"], token, True)
                published += 1
                continue
            review_outcome = publish_review(
                repo,
                pr,
                head,
                review["findings"],
                entry["bot_login"],
                token,
                False,
            )
            check_outcome = publish_check(
                repo, head, review["findings"], token, False
            )
            write_marker(Path(args.state_dir), path.stem, review, url)
            ledger.finish(db, repo, pr, head, "published")
            mark_bundle(
                bundle,
                "approved" if not review["findings"] else "changes-requested",
            )
            path.replace(done_dir / path.name)
            retire_bundle(bundle, done_dir)
            published += 1
            print(
                f"PUBLISHED {path.name} {url or 'no-comment'} "
                f"{verdict(review['findings'])} {review_outcome}/{check_outcome}"
            )
        except Exception as exc:
            print(f"ERROR {path.name}: {exc}", file=sys.stderr)

    db.close()
    print(f"published={published}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
