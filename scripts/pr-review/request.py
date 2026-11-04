#!/usr/bin/env python3
"""Requeue one PR head for an on-demand review.

Local replacement for a comment-command trigger. The caller passes the live
head (the local ``just`` recipe reads it with the operator's own ``gh`` auth),
so a review is requested for exactly the commit the operator sees.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

import ledger

ACTIVE = ("queued", "leased", "reusing")


def latest(db, repo: str, pr: int):
    return db.execute(
        "SELECT * FROM reviews WHERE repo = ? AND pr = ? "
        "ORDER BY requested_at DESC, rowid DESC LIMIT 1",
        (repo, pr),
    ).fetchone()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--state-dir", default="/var/lib/hermes-pr-review")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--head", default="")
    args = parser.parse_args()

    db = ledger.connect(args.ledger)
    try:
        row = (
            ledger.get(db, args.repo, args.pr, args.head)
            if args.head
            else latest(db, args.repo, args.pr)
        )
        if row is None:
            print(
                f"NO-REVIEW {args.repo}#{args.pr}: the collector will queue the "
                "live head on its next run"
            )
            return 0
        if not ledger.valid_bundle(row):
            # The ledger is agent-writable; never turn its strings into root
            # paths or marker names.
            print(
                f"INVALID {args.repo}#{args.pr}: ledger bundle does not match "
                "repo, PR and head",
                file=sys.stderr,
            )
            return 2
        if row["state"] in ACTIVE:
            print(f"ALREADY {row['state']} {row['head']}")
            return 0

        data_dir = Path(args.data_dir)
        bid = ledger.bundle_id(row["repo"], row["pr"], row["head"])
        shutil.rmtree(data_dir / "review-in" / bid, ignore_errors=True)
        for suffix in (".json", ".json.tmp"):
            (data_dir / "review-out" / f"{bid}{suffix}").unlink(missing_ok=True)
        # The publication marker is keyed by head and outlives a publish. Clear
        # it so a waiter cannot mistake the old verdict for this request.
        (Path(args.state_dir) / "published" / f"{row['head']}.json").unlink(
            missing_ok=True
        )
        ledger.requeue(db, row["repo"], row["pr"], row["head"])
        print(
            f"REQUEUED {row['repo']}#{row['pr']} {row['head']} "
            f"(was {row['state']}, {int(time.time() - row['updated_at'])}s ago)"
        )
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
