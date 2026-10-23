#!/usr/bin/env python3
"""Verify the rendered PR review credentials without printing them.

Run on Discovery after vault-agent has rendered the files.

Examples:
  verify-credentials.py --app-credential /run/vault-agent/hermes-pr-review-app.json \
    --upstream-token-file /run/vault-agent/hermes-pr-review-upstream.env \
    --app-repo ErikBPF/aster --upstream-repo apache/datafusion-comet
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tokens  # noqa: E402


def gh(args: list[str], token: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        env=tokens.gh_env(token),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-credential", required=True)
    parser.add_argument("--app-token-cache", required=True)
    parser.add_argument("--upstream-token-file", required=True)
    parser.add_argument("--app-repo", default="")
    parser.add_argument("--upstream-repo", default="")
    args = parser.parse_args()

    failures = 0

    if args.app_repo:
        try:
            data = json.loads(Path(args.app_credential).read_text())
            token = tokens._app_token(args.app_credential, args.app_token_cache)
            proc = gh(["api", "--paginate", "--slurp", "installation/repositories"], token)
            if proc.returncode != 0:
                raise RuntimeError(proc.stderr.strip())
            pages = json.loads(proc.stdout)
            repos = [
                item["full_name"]
                for page in pages
                for item in page.get("repositories", [])
            ]
            present = args.app_repo in repos
            print(
                f"app id {data['app_id']}: {len(repos)} repositories installed; "
                f"{args.app_repo} {'present' if present else 'MISSING'}"
            )
            failures += 0 if present else 1
        except Exception as exc:
            print(f"app credential failed: {exc}", file=sys.stderr)
            failures += 1

    if args.upstream_repo:
        try:
            token = tokens.token_for(
                {"credential": "upstream"}, args.app_credential, args.app_token_cache
            )
            user = gh(["api", "user", "--jq", ".login"], token)
            if user.returncode != 0:
                raise RuntimeError(user.stderr.strip())
            repo = gh(
                [
                    "api",
                    f"repos/{args.upstream_repo}",
                    "--jq",
                    ".permissions",
                ],
                token,
            )
            if repo.returncode != 0:
                raise RuntimeError(repo.stderr.strip())
            print(f"upstream login: {user.stdout.strip()}")
            print(f"upstream permissions on {args.upstream_repo}: {repo.stdout.strip()}")
            if json.loads(repo.stdout).get("push"):
                print("WARNING: upstream token has push permission", file=sys.stderr)
                failures += 1
        except Exception as exc:
            print(f"upstream credential failed: {exc}", file=sys.stderr)
            failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
