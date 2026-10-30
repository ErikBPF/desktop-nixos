#!/usr/bin/env python3
"""Lease exactly one queued review head from the ledger.

Prints ``CLAIM <bundle>`` or ``NO_CLAIM``. The lease is atomic across workers:
SQLite's immediate transaction serialises the scan and the update. An expired
lease may be taken over, so a worker that dies mid-review does not block the
head for the full claim TTL.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import ledger


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", default=f"worker-{os.getpid()}")
    parser.add_argument("--claim-ttl", type=int, default=1800)
    parser.add_argument("--max-attempts", type=int, default=3)
    args = parser.parse_args()

    path = os.environ.get(
        "HERMES_REVIEW_LEDGER", "/opt/data/review-ledger/ledger.db"
    )
    root = Path(os.environ.get("HERMES_REVIEW_IN", "/opt/data/review-in"))
    if not root.is_dir():
        print("NO_CLAIM")
        return 0
    db = ledger.connect(path)
    try:
        for _ in range(50):
            row = ledger.claim(db, args.worker, args.claim_ttl, args.max_attempts)
            if row is None:
                print("NO_CLAIM")
                return 0
            bundle = row["bundle"]
            if (root / bundle / ".ready").exists():
                print(f"CLAIM {bundle}")
                return 0
            ledger.finish(
                db, row["repo"], row["pr"], row["head"], "stale", "bundle missing"
            )
        print("NO_CLAIM")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
