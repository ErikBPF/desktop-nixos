#!/usr/bin/env python3
"""Apply the hackerman-cr ruleset to personal repositories.

Public repositories can enforce the gate on GitHub Free. Private repositories
need GitHub Pro, so they are skipped unless --include-private is passed.

The ruleset requires the App's check run and one approving review, with stale
approvals dismissed on push. It has no bypass actors. Run with --apply to write;
the default is a dry run.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

GH = "gh"
RULE_NAME = "hackerman-cr gate"
CHECK_NAME = "hackerman-cr/evaluation"
APP_ID = 5434668


def gh_json(args: list[str]) -> object:
    proc = subprocess.run([GH, *args], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"gh {' '.join(args)} failed ({proc.returncode}): {proc.stderr.strip()}"
        )
    return json.loads(proc.stdout)


def gh_api(method: str, endpoint: str, payload: dict) -> object:
    proc = subprocess.run(
        [GH, "api", "--method", method, endpoint, "--input", "-"],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"gh api {method} {endpoint} failed ({proc.returncode}): "
            f"{proc.stderr.strip()}"
        )
    return json.loads(proc.stdout)


def ruleset_payload(
    required_approvals: int, integration_id: int = APP_ID
) -> dict:
    return {
        "name": RULE_NAME,
        "target": "branch",
        "enforcement": "active",
        "conditions": {
            "ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}
        },
        "bypass_actors": [],
        "rules": [
            {
                "type": "pull_request",
                "parameters": {
                    "required_approving_review_count": required_approvals,
                    "dismiss_stale_reviews_on_push": True,
                    "require_code_owner_review": False,
                    "require_last_push_approval": False,
                    "required_review_thread_resolution": False,
                },
            },
            {
                "type": "required_status_checks",
                "parameters": {
                    "strict_required_status_checks_policy": True,
                    "do_not_enforce_on_create": False,
                    "required_status_checks": [
                        {
                            "context": CHECK_NAME,
                            "integration_id": integration_id,
                        }
                    ],
                },
            },
        ],
    }


def apply(repo: str, payload: dict, apply_changes: bool) -> str:
    rulesets = gh_json(["api", f"repos/{repo}/rulesets?per_page=100"])
    existing = next(
        (item for item in rulesets if item.get("name") == RULE_NAME), None
    )
    if not apply_changes:
        return "UPDATE" if existing else "CREATE"
    if existing:
        gh_api("PUT", f"repos/{repo}/rulesets/{existing['id']}", payload)
        return "UPDATED"
    gh_api("POST", f"repos/{repo}/rulesets", payload)
    return "CREATED"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repos", nargs="*", help="owner/name entries")
    parser.add_argument("--config", help="repos JSON with a repos list")
    parser.add_argument(
        "--required-approvals",
        type=int,
        default=0,
        help="Approvals required in addition to the check. GitHub does not count "
        "App approvals, so the default is check-only.",
    )
    parser.add_argument("--integration-id", type=int, default=APP_ID)
    parser.add_argument(
        "--include-private",
        action="store_true",
        help="attempt private repos too (needs GitHub Pro)",
    )
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    repos = list(args.repos)
    if args.config:
        repos.extend(
            entry["repo"] for entry in json.loads(Path(args.config).read_text())["repos"]
        )
    repos = sorted(set(repos))
    if not repos:
        parser.error("no repositories given")

    payload = ruleset_payload(args.required_approvals, args.integration_id)
    failures = 0
    for repo in repos:
        try:
            visibility = gh_json(["api", f"repos/{repo}"])["visibility"]
            if visibility == "private" and not args.include_private:
                print(f"SKIP {repo}: private repositories need GitHub Pro")
                continue
            outcome = apply(repo, payload, args.apply)
            print(f"{outcome} {repo}")
        except Exception as exc:
            failures += 1
            print(f"ERROR {repo}: {exc}", file=sys.stderr)

    print(f"repos={len(repos)} failures={failures} apply={args.apply}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
