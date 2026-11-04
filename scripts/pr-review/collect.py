#!/usr/bin/env python3
"""Collect PR review bundles for the Hermes cr-pr skill.

Runs on the host with repo-scoped credentials. Writes one immutable bundle per
PR head under the agent data dir. The agent never sees a token.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import ledger
import tokens

GH = "gh"
# The required check's name. `tests/pr-review-publish.py` asserts it matches
# the publisher's constant.
CHECK_NAME = "hackerman-cr/evaluation"


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


def gh_bytes(args: list[str], token: str) -> bytes:
    proc = subprocess.run(
        [GH, *args], check=True, capture_output=True, env=tokens.gh_env(token)
    )
    return proc.stdout


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
    return json.loads(proc.stdout or "{}")


def fetch_file(
    repo: str, path: str, ref: str, dest: Path, token: str
) -> bool:
    proc = subprocess.run(
        [
            GH,
            "api",
            f"repos/{repo}/contents/{path}?ref={ref}",
            "-H",
            "Accept: application/vnd.github.raw",
        ],
        capture_output=True,
        env=tokens.gh_env(token),
    )
    if proc.returncode != 0:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(proc.stdout)
    return True


def fetch_skills(repo: str, base: str, dest: Path, token: str) -> int:
    proc = subprocess.run(
        ["gh", "api", f"repos/{repo}/contents/.ai/skills?ref={base}"],
        capture_output=True,
        text=True,
        env=tokens.gh_env(token),
    )
    if proc.returncode != 0:
        if "HTTP 404" in proc.stderr or "Not Found" in proc.stderr:
            return 0
        raise RuntimeError(
            f"gh api .ai/skills failed ({proc.returncode}): {proc.stderr.strip()}"
        )
    entries = json.loads(proc.stdout)
    count = 0
    for entry in entries:
        if entry.get("type") != "dir":
            continue
        name = entry["name"]
        if fetch_file(
            repo,
            f".ai/skills/{name}/SKILL.md",
            base,
            dest / f"{name}.md",
            token,
        ):
            count += 1
    return count


def fetch_docs(repo: str, base: str, dest: Path, token: str) -> int:
    paths = [
        "AGENTS.md",
        "CLAUDE.md",
        "CONTRIBUTING.md",
        ".ai/skills/README.md",
        ".cursorrules",
    ]
    count = 0
    for path in paths:
        if fetch_file(repo, path, base, dest / path, token):
            count += 1
    # Contributor guides where the repository keeps them.
    for path in (
        "docs/source/contributor-guide/index.md",
        "docs/source/contributor-guide/development.md",
    ):
        if fetch_file(repo, path, base, dest / path, token):
            count += 1
    return count


def bundle_id(repo: str, pr: int, head: str) -> str:
    return ledger.bundle_id(repo, pr, head)


def ignore_reason(entry: dict, pr: dict) -> str | None:
    """Return why this PR is skipped, or None.

    Filters only stop a new head from being bundled; an already queued or
    published head keeps its state. An invalid title pattern fails open so a
    typo cannot blind the gate, but is reported on stderr.
    """
    author = str((pr.get("author") or {}).get("login") or "").casefold()
    authors = {str(item).casefold() for item in entry.get("ignore_authors") or []}
    if author and author in authors:
        return f"author {author}"

    labels = {
        str((label.get("name") if isinstance(label, dict) else label) or "").casefold()
        for label in pr.get("labels") or []
    }
    ignored = {str(item).casefold() for item in entry.get("ignore_labels") or []}
    hit = labels & ignored
    if hit:
        return f"label {sorted(hit)[0]}"

    pattern = entry.get("ignore_title") or ""
    if pattern:
        try:
            if re.search(pattern, str(pr.get("title") or "")):
                return f"title matches {pattern!r}"
        except re.error as exc:
            print(
                f"WARN {entry.get('repo')}: invalid ignore_title regex: {exc}",
                file=sys.stderr,
            )
    return None


def publish_skip_check(repo: str, head: str, reason: str, token: str) -> bool:
    """Satisfy the required check on a head the filters deliberately skipped.

    A missing check blocks the PR, which defeats the point of skipping bot PRs.
    ``neutral`` passes a required status check without claiming a review.
    Never overwrite an existing run for the same head: a real verdict wins.
    """
    query = (
        f"repos/{repo}/commits/{head}/check-runs"
        f"?check_name={CHECK_NAME}&per_page=100"
    )
    runs = gh_json(["api", query], token).get("check_runs", [])
    if any(run.get("name") == CHECK_NAME for run in runs):
        return False
    gh_api(
        "POST",
        f"repos/{repo}/check-runs",
        token,
        {
            "name": CHECK_NAME,
            "head_sha": head,
            "status": "completed",
            "conclusion": "neutral",
            "output": {
                "title": f"Skipped: {reason}",
                "summary": (
                    "This head matched a review filter, so hackerman-cr did "
                    "not review it. Remove the author, label, or title match "
                    "to request a review."
                ),
            },
        },
    )
    return True


def reuse_review(previous: dict, head: str, base: str) -> dict:
    """Copy a published verdict onto an identical diff at a new head."""
    review = json.loads(json.dumps(previous))
    old_head = str(review.get("head") or "")[:7]
    old_base = str(review.get("base") or "")[:7]
    review["head"] = head
    review["base"] = base
    review["limits"] = [
        item
        for item in review.get("limits") or []
        if "identical to" not in str(item)
    ] + [
        f"Diff and repository guidance are identical to {old_head} "
        f"(base {old_base}). The previous verdict was reused without a new "
        "model run."
    ]
    return review


def guidance_snapshot(root: Path) -> dict[str, bytes]:
    """Base-pinned contributor guidance, compared byte for byte before reuse."""
    snapshot: dict[str, bytes] = {}
    for directory in ("docs", "skills"):
        source = root / directory
        if not source.exists():
            continue
        for path in sorted(source.rglob("*")):
            if path.is_file():
                snapshot[str(path.relative_to(root))] = path.read_bytes()
    return snapshot


def prune_repo_bundles(
    in_dir: Path,
    db,
    repo: str,
    heads: dict[int, str],
) -> int:
    """Drop bundles whose PR closed, or whose head a newer bundle superseded.

    The ledger owns the head state, so this only cleans the inbox. A live lease
    is never removed: a worker may still be reading that bundle.
    """
    owner, name = repo.split("/", 1)
    prefix = f"{owner}__{name}__"
    removed = 0
    now = time.time()
    for bundle in in_dir.iterdir():
        if not bundle.is_dir() or not bundle.name.startswith(prefix):
            continue
        parts = bundle.name.split("__")
        if len(parts) < 4:
            continue
        try:
            number = int(parts[-2])
        except ValueError:
            continue
        current = heads.get(number)
        row = ledger.get_bundle(db, bundle.name)
        if row is not None and (row["repo"] != repo or not ledger.valid_bundle(row)):
            row = None
        if row is not None:
            current = heads.get(row["pr"])
        keep = current is not None and current.startswith(parts[-1])
        if keep:
            continue
        if row is not None and row["state"] == "leased":
            if (row["lease_expires"] or 0) > now:
                continue
        if row is not None and row["state"] == "reusing":
            (in_dir.parent / "review-out" / f"{bundle.name}.json").unlink(
                missing_ok=True
            )
        if row is not None and row["state"] not in ("published", "stale"):
            ledger.finish(
                db, row["repo"], row["pr"], row["head"], "stale", "bundle pruned"
            )
        shutil.rmtree(bundle, ignore_errors=True)
        removed += 1
    return removed


def reconcile_closed(db, repo: str, open_numbers: set[int]) -> int:
    """Mark heads of closed or merged PRs stale.

    The collector only lists open PRs, so this is the only place a terminal
    row can learn that its PR will never be reviewed again. Live leases are
    left alone until they expire.
    """
    now = time.time()
    marked = 0
    for row in db.execute(
        "SELECT * FROM reviews WHERE repo = ? AND state IN ('queued', 'failed', 'leased')",
        (repo,),
    ).fetchall():
        if row["pr"] in open_numbers:
            continue
        if row["state"] == "leased" and (row["lease_expires"] or 0) > now:
            continue
        ledger.finish(
            db, row["repo"], row["pr"], row["head"], "stale", "PR closed or merged"
        )
        marked += 1
    return marked


def migrate_markers(marker_dir: Path) -> int:
    """Rename pre-head marker files to their recorded head and lock modes."""
    if not marker_dir.is_dir():
        return 0
    moved = 0
    marker_dir.chmod(0o700)
    for path in marker_dir.glob("*.json"):
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        head = data.get("head")
        if not head:
            continue
        target = marker_dir / f"{head}.json"
        if target != path:
            if not target.exists():
                target.write_text(path.read_text())
            path.unlink(missing_ok=True)
            moved += 1
        target.chmod(0o600)
    return moved


def marker_matches(marker_dir: Path, head: str) -> bool:
    path = marker_dir / f"{head}.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return False
    return data.get("head") == head


def backfill_markers(db, marker_dir: Path, state_path: Path) -> int:
    """Create publication markers once from the root-owned pre-ledger record.

    The ledger lives on the agent-writable data mount, so it cannot mint its
    own proof of publication. Only heads recorded as posted in the root-only
    ``state.json`` get a marker; rows planted in the ledger are ignored.
    """
    if not state_path.exists():
        return 0
    try:
        state = json.loads(state_path.read_text())
    except (OSError, ValueError):
        return 0
    marker_dir.mkdir(parents=True, exist_ok=True)
    marker_dir.chmod(0o700)
    written = 0
    for key, entry in state.get("prs", {}).items():
        repo, _, number = key.rpartition("#")
        try:
            pr = int(number)
        except ValueError:
            continue
        head = entry.get("posted_head")
        if not repo or not head:
            continue
        row = ledger.get(db, repo, pr, head)
        if row is None or row["state"] != "published":
            continue
        target = marker_dir / f"{row['head']}.json"
        if target.exists():
            continue
        target.write_text(
            json.dumps(
                {"repo": row["repo"], "pr": row["pr"], "head": row["head"]},
                indent=2,
            )
            + "\n"
        )
        target.chmod(0o600)
        written += 1
    return written


def repo_context(data_dir: Path, repo: str, current_pr: int, keep: int = 10) -> str:
    """Earlier reviews from this repository and no other.

    Hermes' built-in memory and session_search are container-wide, so they
    cannot be scoped to a repository. This file is the scoped substitute: the
    collector builds it from published reviews whose `repo` field matches.
    """
    done = data_dir / "review-done"
    entries = []
    prefix = repo.replace("/", "__", 1) + "__"
    if done.is_dir():
        for path in done.glob(f"{prefix}*.json"):
            try:
                review = json.loads(path.read_text())
            except (OSError, ValueError):
                continue
            if review.get("repo") != repo or review.get("pr") == current_pr:
                continue
            entries.append((path.stat().st_mtime, review))
    entries.sort(key=lambda item: item[0], reverse=True)

    lines = [
        f"# Earlier reviews in {repo}",
        "",
        "Background only: other PRs in the same repository. Do not treat them "
        "as findings about the current diff, and do not infer anything from "
        "any other repository.",
        "",
    ]
    for _, review in entries[:keep]:
        summary = str(review.get("summary", "")).strip().replace("\n", " ")[:300]
        lines.append(
            f"- PR #{review.get('pr')} ({str(review.get('head', ''))[:12]}): {summary}"
        )
        for finding in review.get("findings", [])[:5]:
            lines.append(
                "  - {severity} {file}:{line} {title}".format(
                    severity=finding.get("severity", "?"),
                    file=finding.get("file", "?"),
                    line=finding.get("line", "?"),
                    title=str(finding.get("title", "")).strip(),
                )
            )
    if not entries:
        lines.append("- No earlier published review for this repository.")
    return "\n".join(lines) + "\n"


def migrate_state(db, state_path: Path, in_dir: Path) -> int:
    """Import the pre-ledger state file once, so live heads are not re-reviewed.

    Requested heads whose bundle was already pruned are skipped: the collector
    rebuilds them only while the PR is still open and its head unchanged.
    """
    if ledger.count(db) or not state_path.exists():
        return 0
    try:
        state = json.loads(state_path.read_text())
    except (OSError, ValueError):
        return 0
    imported = 0
    db.execute("BEGIN IMMEDIATE")
    try:
        for key, entry in state.get("prs", {}).items():
            repo, _, number = key.rpartition("#")
            try:
                pr = int(number)
            except ValueError:
                continue
            posted = entry.get("posted_head")
            head = posted or entry.get("requested_head")
            if not repo or not head:
                continue
            bundle = bundle_id(repo, pr, head)
            if not posted and not (in_dir / bundle / ".ready").exists():
                continue
            ledger.record(db, repo, pr, head, entry.get("base", ""), bundle)
            if posted == head:
                ledger.finish(db, repo, pr, head, "published")
            imported += 1
        db.execute("COMMIT")
    except Exception:
        db.execute("ROLLBACK")
        raise
    return imported


def harden_bundle(root: Path) -> None:
    """Strip group/other write so the reviewed agent cannot edit its own inputs."""
    for path in [root, *root.rglob("*")]:
        path.chmod(0o755 if path.is_dir() else 0o644)


def reuse_bundle(
    args,
    db,
    repo: str,
    number: int,
    head: str,
    base: str,
    bid: str,
    digest: str,
    previous,
    token: str,
) -> Path | None:
    """Publish a copied verdict for an identical diff instead of reviewing again.

    The publisher still needs a bundle for evidence checks and a ledger row for
    identity. Copying the previous bundle keeps the same evidence files
    (``diff.patch``, ``docs/``, ``skills/``) available, so a finding that quotes
    repository guidance is not silently dropped. A ``reusing`` row is never
    claimable. The packet is renamed into place last: a half-written reuse is
    discarded by the collector and reviewed for real.
    """
    if not ledger.valid_bundle(previous):
        print(
            f"WARN {repo}#{number}: refused invalid ledger bundle for reuse",
            file=sys.stderr,
        )
        return None
    previous_bid = ledger.bundle_id(repo, number, str(previous["head"]))
    data_dir = Path(args.data_dir)
    target = data_dir / "review-in" / bid
    source = data_dir / "review-done" / previous_bid
    packet = data_dir / "review-done" / f"{previous_bid}.json"
    if not source.is_dir():
        return None
    try:
        reused = reuse_review(json.loads(packet.read_text()), head, base)
    except (OSError, ValueError) as exc:
        print(f"WARN {repo}#{number}: cannot reuse {packet.name}: {exc}", file=sys.stderr)
        return None
    out_dir = data_dir / "review-out"
    out_dir.mkdir(parents=True, exist_ok=True)
    staged = out_dir / f"{bid}.json.tmp"
    old_umask = os.umask(0o022)
    try:
        tmp = target.with_name(target.name + ".tmp")
        if tmp.exists():
            shutil.rmtree(tmp)
        shutil.copytree(source, tmp)
        for stale in (".ready", ".posted"):
            (tmp / stale).unlink(missing_ok=True)
        # The previous bundle's guidance was fetched at the old base. Reuse is
        # only honest when that guidance still matches the new base; a changed
        # rule can change the verdict, so fall back to a real review.
        before = guidance_snapshot(tmp)
        for directory in ("docs", "skills"):
            shutil.rmtree(tmp / directory, ignore_errors=True)
        fetch_skills(repo, base, tmp / "skills", token)
        fetch_docs(repo, base, tmp / "docs", token)
        if guidance_snapshot(tmp) != before:
            print(
                f"REFRESH {repo}#{number}: guidance changed at {base[:7]}; "
                "reviewing instead of reusing",
                file=sys.stderr,
            )
            shutil.rmtree(tmp, ignore_errors=True)
            return None
        (tmp / "meta.json").write_text(
            json.dumps(
                {
                    "repo": repo,
                    "pr": number,
                    "head": head,
                    "base": base,
                    "reused_from": previous["head"],
                },
                indent=2,
            )
            + "\n"
        )
        (tmp / "request.md").write_text(
            "\n".join(
                [
                    "# Review request",
                    "",
                    f"Bundle: `{bid}`",
                    f"Repository: `{repo}`",
                    f"PR: `{number}`",
                    f"Base: `{base}`",
                    f"Head: `{head}`",
                    "",
                    f"Verdict reused from `{previous['head']}`: diff and "
                    "base-pinned guidance are identical.",
                    "No model run. Do not modify the PR or the bundle.",
                    "",
                ]
            )
        )
        (tmp / ".reuse").write_text(now() + "\n")
        harden_bundle(tmp)
        tmp.replace(target)
        staged.write_text(json.dumps(reused, indent=2) + "\n")

        ledger.mark_reusing(db, repo, number, head, base, bid, digest)
        row = ledger.get(db, repo, number, head)
        if row is None or row["state"] != "reusing":
            # A live row (for example a leased worker) owns this head; do not
            # hand the publisher a second packet for it.
            shutil.rmtree(target, ignore_errors=True)
            staged.unlink(missing_ok=True)
            return None
        ledger.supersede(db, repo, number, head)
        staged.replace(out_dir / f"{bid}.json")
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        staged.unlink(missing_ok=True)
        raise
    finally:
        os.umask(old_umask)
    print(f"REUSED {bid} from {str(previous['head'])[:7]}")
    return target


def build_bundle(
    args, entry: dict, pr: dict, db, token: str
) -> Path | None:
    repo = entry["repo"]
    number = pr["number"]
    head = pr["headRefOid"]
    base = pr["baseRefOid"]
    bid = bundle_id(repo, number, head)
    data_dir = Path(args.data_dir)
    target = data_dir / "review-in" / bid
    row = ledger.get(db, repo, number, head)
    if row is not None and row["state"] in ("published", "stale", "failed", "reusing"):
        return None
    # Reuse is only for a head the ledger has never seen. An existing queued
    # row means a retry or an explicit on-demand request; both run the model.
    fresh_head = row is None
    if target.exists():
        if row is not None:
            return None
        if (target / ".reuse").exists():
            # A reuse that never reached the ledger is not reviewable input.
            shutil.rmtree(target, ignore_errors=True)
            (data_dir / "review-out" / f"{bid}.json.tmp").unlink(missing_ok=True)
        else:
            ledger.record(db, repo, number, head, base, bid)
            print(f"REQUESTED {bid}")
            return target

    diff = gh_bytes(["pr", "diff", str(number), "--repo", repo], token)
    digest = hashlib.sha256(diff).hexdigest()
    previous = ledger.last_published(db, repo, number) if fresh_head else None
    if previous is not None and previous["diff_hash"] == digest:
        reused = reuse_bundle(
            args, db, repo, number, head, base, bid, digest, previous, token
        )
        if reused is not None:
            return reused

    tmp = target.with_name(target.name + ".tmp")
    if tmp.exists():
        shutil.rmtree(tmp)
    old_umask = os.umask(0o022)
    try:
        tmp.mkdir(parents=True)
        view = gh_json(
            [
                "pr",
                "view",
                str(number),
                "--repo",
                repo,
                "--json",
                "title,body,author,isDraft,state,files,baseRefOid,headRefOid,url",
            ],
            token,
        )
        (tmp / "meta.json").write_text(json.dumps(view, indent=2) + "\n")
        (tmp / "diff.patch").write_bytes(diff)
        for name, endpoint in (
            ("reviews.json", "reviews"),
            ("review_comments.json", "comments"),
        ):
            data = gh_json(
                ["api", f"repos/{repo}/pulls/{number}/{endpoint}?per_page=100"],
                token,
            )
            (tmp / name).write_text(json.dumps(data, indent=2) + "\n")
        issue_comments = gh_json(
            ["api", f"repos/{repo}/issues/{number}/comments?per_page=100"], token
        )
        (tmp / "issue_comments.json").write_text(
            json.dumps(issue_comments, indent=2) + "\n"
        )

        checks = subprocess.run(
            [GH, "pr", "checks", str(number), "--repo", repo],
            capture_output=True,
            text=True,
            env=tokens.gh_env(token),
        )
        checks_text = (checks.stdout or "").strip()
        if checks.stderr.strip():
            checks_text += "\n" + checks.stderr.strip()
        (tmp / "checks.txt").write_text(
            (checks_text or "No checks reported.") + "\n"
        )

        files = view.get("files", [])
        (tmp / "files.txt").write_text(
            "".join(f"{item['path']}\n" for item in files)
        )
        (tmp / "repo-context.md").write_text(
            repo_context(Path(args.data_dir), repo, number)
        )

        skills = fetch_skills(repo, base, tmp / "skills", token)
        docs = fetch_docs(repo, base, tmp / "docs", token)
        (tmp / "request.md").write_text(
            "\n".join(
                [
                    "# Review request",
                    "",
                    f"Bundle: `{bid}`",
                    f"Repository: `{repo}`",
                    f"PR: `{number}`",
                    f"Base: `{base}`",
                    f"Head: `{head}`",
                    f"Skills fetched: {skills}",
                    f"Docs fetched: {docs}",
                    "",
                    "Use the `cr-pr` skill.",
                    "Read `repo-context.md` for earlier reviews of this repository only.",
                    f"Write the review JSON to `/opt/data/review-out/{bid}.json`.",
                    "Do not post to GitHub. Do not modify the PR or the bundle.",
                    "",
                ]
            )
        )
        (tmp / ".ready").write_text(now() + "\n")
        harden_bundle(tmp)
        tmp.replace(target)
    except Exception:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    finally:
        os.umask(old_umask)

    ledger.record(db, repo, number, head, base, bid, digest)
    ledger.supersede(db, repo, number, head)
    print(f"REQUESTED {bid}")
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--app-credential", required=True)
    parser.add_argument("--app-token-cache", required=True)
    parser.add_argument("--ledger", default=None)
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--retry-after-minutes", type=int, default=45)
    args = parser.parse_args()

    config = tokens.load_config(args.config)
    settings = tokens.load_settings(args.config)
    review_drafts = bool(settings.get("review_drafts", True))
    state_dir = Path(args.state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    state_path = state_dir / "state.json"
    lock_path = state_dir / "collect.lock"
    lock = lock_path.open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("collector already running", file=sys.stderr)
        lock.close()
        return 0

    in_dir = Path(args.data_dir) / "review-in"
    ledger_path = args.ledger or str(
        Path(args.data_dir) / "review-ledger" / "ledger.db"
    )
    db = ledger.connect(ledger_path)
    migrated = migrate_state(db, state_path, in_dir)
    marker_dir = state_dir / "published"
    marker_moves = migrate_markers(marker_dir)
    markers = backfill_markers(db, marker_dir, state_path)
    in_dir.mkdir(parents=True, exist_ok=True)
    (Path(args.data_dir) / "review-out").mkdir(parents=True, exist_ok=True)

    requested = 0
    pruned = 0
    closed = 0
    for entry in config:
        repo = entry["repo"]
        try:
            token = tokens.token_for(
                entry, args.app_credential, args.app_token_cache
            )
            prs = gh_json(
                [
                    "pr",
                    "list",
                    "--repo",
                    repo,
                    "--state",
                    "open",
                    "--limit",
                    str(args.limit),
                    "--json",
                    "number,title,author,labels,isDraft,headRefOid,baseRefOid,url,updatedAt",
                ],
                token,
            )
        except Exception as exc:
            print(f"ERROR {repo}: {exc}", file=sys.stderr)
            continue

        heads = {item["number"]: item["headRefOid"] for item in prs}
        if len(prs) < args.limit:
            pruned += prune_repo_bundles(in_dir, db, repo, heads)
            closed += reconcile_closed(db, repo, set(heads))

        for pr in prs:
            key = f"{repo}#{pr['number']}"
            head = pr["headRefOid"]
            reason = ignore_reason(entry, pr)
            if reason:
                print(f"IGNORED {key} ({reason})")
                try:
                    if publish_skip_check(repo, head, reason, token):
                        print(f"SKIP-CHECK {key}")
                except Exception as exc:  # keep the other PRs moving
                    print(f"ERROR {key}: skip check: {exc}", file=sys.stderr)
                continue
            if pr.get("isDraft") and not review_drafts:
                print(f"SKIP-DRAFT {key}")
                continue
            row = ledger.get(db, repo, pr["number"], head)
            if row is not None:
                if row["state"] == "reusing":
                    # The publisher has only the copied packet; without it,
                    # fall back to a real review at this head. The ledger is
                    # agent-writable, so never trust its strings as paths.
                    if not ledger.valid_bundle(row):
                        print(
                            f"ERROR {key}: invalid ledger bundle; not touching paths",
                            file=sys.stderr,
                        )
                        ledger.finish(
                            db,
                            repo,
                            pr["number"],
                            head,
                            "failed",
                            "invalid bundle name",
                        )
                        continue
                    bid = ledger.bundle_id(repo, pr["number"], head)
                    out_dir = Path(args.data_dir) / "review-out"
                    if (out_dir / f"{bid}.json").exists():
                        continue
                    shutil.rmtree(
                        Path(args.data_dir) / "review-in" / bid,
                        ignore_errors=True,
                    )
                    (out_dir / f"{bid}.json.tmp").unlink(missing_ok=True)
                    ledger.requeue(db, repo, pr["number"], head)
                    row = ledger.get(db, repo, pr["number"], head)
                if row["state"] == "published":
                    if marker_matches(marker_dir, row["head"]):
                        continue
                    ledger.requeue(db, repo, pr["number"], head)
                    row = ledger.get(db, repo, pr["number"], head)
                if row["state"] == "stale":
                    # Closed/reopened PRs and false stale marks are safe to
                    # revive: nothing was published for this head.
                    ledger.requeue(db, repo, pr["number"], head)
                    row = ledger.get(db, repo, pr["number"], head)
                if row is not None and row["state"] == "leased":
                    if (row["lease_expires"] or 0) > time.time():
                        continue
                if row is not None and row["state"] == "failed":
                    age = time.time() - row["updated_at"]
                    if age < args.retry_after_minutes * 60:
                        continue
                    ledger.requeue(db, repo, pr["number"], head)
            try:
                if build_bundle(args, entry, pr, db, token):
                    requested += 1
            except Exception as exc:  # keep the other PRs moving
                print(f"ERROR {key}: {exc}", file=sys.stderr)

    db.close()
    lock.close()
    print(
        f"requested={requested} pruned={pruned} closed={closed} "
        f"markers={markers} moved={marker_moves} migrated={migrated}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
