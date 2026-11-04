#!/usr/bin/env python3
"""Requeue one PR head for an on-demand review.

Local replacement for a comment-command trigger. The caller passes the live
head (the local ``just`` recipe reads it with the operator's own ``gh`` auth),
so a review is requested for exactly the commit the operator sees.
"""

from __future__ import annotations

import argparse
import shutil
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
        if row["state"] in ACTIVE:
            print(f"ALREADY {row['state']} {row['head']}")
            return 0

        data_dir = Path(args.data_dir)
        shutil.rmtree(data_dir / "review-in" / row["bundle"], ignore_errors=True)
        for suffix in (".json", ".json.tmp"):
            (data_dir / "review-out" / f"{row['bundle']}{suffix}").unlink(
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
