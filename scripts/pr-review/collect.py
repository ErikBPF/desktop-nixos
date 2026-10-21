#!/usr/bin/env python3
"""Collect Comet PR review bundles for the Hermes cr-pr skill.

Runs on the host with a bot token. Writes one immutable bundle per PR head under
the agent data dir. The agent never sees the token.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

GH = "gh"


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def run(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=check, capture_output=True, text=True)


def gh_json(args: list[str]) -> object:
    proc = subprocess.run([GH, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"gh {' '.join(args)} failed ({proc.returncode}): {proc.stderr.strip()}"
        )
    return json.loads(proc.stdout)


def gh_bytes(args: list[str]) -> bytes:
    proc = subprocess.run([GH, *args], check=True, capture_output=True)
    return proc.stdout


def fetch_file(repo: str, path: str, ref: str, dest: Path) -> bool:
    proc = subprocess.run(
        [
            GH,
            "api",
            f"repos/{repo}/contents/{path}?ref={ref}",
            "-H",
            "Accept: application/vnd.github.raw",
        ],
        capture_output=True,
    )
    if proc.returncode != 0:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(proc.stdout)
    return True


def fetch_skills(repo: str, base: str, dest: Path) -> int:
    entries = gh_json(["api", f"repos/{repo}/contents/.ai/skills?ref={base}"])
    count = 0
    for entry in entries:
        if entry.get("type") != "dir":
            continue
        name = entry["name"]
        if fetch_file(repo, f".ai/skills/{name}/SKILL.md", base, dest / f"{name}.md"):
            count += 1
    return count


def fetch_docs(repo: str, base: str, dest: Path) -> int:
    paths = [
        "AGENTS.md",
        "CONTRIBUTING.md",
        "docs/source/contributor-guide/index.md",
        "docs/source/contributor-guide/development.md",
    ]
    return sum(
        1 for path in paths if fetch_file(repo, path, base, dest / path)
    )


def bundle_id(repo: str, pr: int, head: str) -> str:
    owner, name = repo.split("/", 1)
    return f"{owner}__{name}__{pr}__{head[:12]}"


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "prs": {}}
    return json.loads(path.read_text())


def save_state(path: Path, state: dict) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def build_bundle(args, pr: dict, state: dict) -> Path | None:
    repo = args.repo
    number = pr["number"]
    head = pr["headRefOid"]
    base = pr["baseRefOid"]
    bid = bundle_id(repo, number, head)
    target = Path(args.data_dir) / "review-in" / bid
    key = f"{repo}#{number}"
    if target.exists():
        entry = state["prs"].get(key, {})
        entry["requested_head"] = head
        entry["requested_at"] = now()
        state["prs"][key] = entry
        return target

    entry = state["prs"].get(key, {})
    tmp = target.with_name(target.name + ".tmp")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    try:
        view = gh_json(
            [
                "pr",
                "view",
                str(number),
                "--repo",
                repo,
                "--json",
                "title,body,author,isDraft,state,files,baseRefOid,headRefOid,url",
            ]
        )
        (tmp / "meta.json").write_text(json.dumps(view, indent=2) + "\n")
        (tmp / "diff.patch").write_bytes(
            gh_bytes(["pr", "diff", str(number), "--repo", repo])
        )
        for name, endpoint in (
            ("reviews.json", "reviews"),
            ("review_comments.json", "comments"),
        ):
            data = gh_json(
                ["api", f"repos/{repo}/pulls/{number}/{endpoint}?per_page=100"]
            )
            (tmp / name).write_text(json.dumps(data, indent=2) + "\n")
        issue_comments = gh_json(
            ["api", f"repos/{repo}/issues/{number}/comments?per_page=100"]
        )
        (tmp / "issue_comments.json").write_text(
            json.dumps(issue_comments, indent=2) + "\n"
        )

        checks = run(
            ["pr", "checks", str(number), "--repo", repo], check=False
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

        skills = fetch_skills(repo, base, tmp / "skills")
        docs = fetch_docs(repo, base, tmp / "docs")
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
                    f"Write the review JSON to `/opt/data/review-out/{bid}.json`.",
                    "Do not post to GitHub. Do not modify the PR or the bundle.",
                    "",
                ]
            )
        )
        (tmp / ".ready").write_text(now() + "\n")
        tmp.replace(target)
    except Exception:
        shutil.rmtree(tmp, ignore_errors=True)
        raise

    entry["requested_head"] = head
    entry["requested_at"] = now()
    state["prs"][key] = entry
    print(f"REQUESTED {bid}")
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--author", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--retry-after-minutes", type=int, default=45)
    args = parser.parse_args()

    state_dir = Path(args.state_dir)
    state_dir.mkdir(parents=True, exist_ok=True)
    state_path = state_dir / "state.json"
    lock_path = state_dir / "collect.lock"
    lock = lock_path.open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("collector already running", file=sys.stderr)
        return 0

    state = load_state(state_path)
    prs = gh_json(
        [
            "pr",
            "list",
            "--repo",
            args.repo,
            "--author",
            args.author,
            "--state",
            "open",
            "--limit",
            str(args.limit),
            "--json",
            "number,title,isDraft,headRefOid,baseRefOid,url,updatedAt",
        ]
    )
    (Path(args.data_dir) / "review-in").mkdir(parents=True, exist_ok=True)
    (Path(args.data_dir) / "review-out").mkdir(parents=True, exist_ok=True)

    requested = 0
    for pr in prs:
        key = f"{args.repo}#{pr['number']}"
        entry = state["prs"].get(key, {})
        head = pr["headRefOid"]
        if entry.get("posted_head") == head:
            continue
        if entry.get("requested_head") == head:
            requested_at = entry.get("requested_at", "")
            try:
                age = time.time() - datetime.fromisoformat(requested_at).timestamp()
            except ValueError:
                age = 0
            if age < args.retry_after_minutes * 60:
                continue
        try:
            if build_bundle(args, pr, state):
                requested += 1
        except Exception as exc:  # keep the other PRs moving
            print(f"ERROR {key}: {exc}", file=sys.stderr)

    save_state(state_path, state)
    lock.close()
    print(f"requested={requested} open={len(prs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
