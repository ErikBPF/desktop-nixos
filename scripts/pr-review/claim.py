#!/usr/bin/env python3
"""Claim exactly one ready review bundle for a cron worker.

Prints ``CLAIM <bundle>`` or ``NO_CLAIM``. Claiming is atomic across workers:
a global flock serialises the scan and one ``.claim`` file is created per
bundle. Oldest bundle first, so a backlog drains instead of starving.

A claim older than ``--claim-ttl`` is treated as abandoned (the reviewing turn
died) and may be taken over.
"""

from __future__ import annotations

import argparse
import fcntl
import os
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", default="worker")
    parser.add_argument("--claim-ttl", type=int, default=3600)
    args = parser.parse_args()

    root = Path(os.environ.get("HERMES_REVIEW_IN", "/opt/data/review-in"))
    out = Path(os.environ.get("HERMES_REVIEW_OUT", "/opt/data/review-out"))
    if not root.is_dir():
        print("NO_CLAIM")
        return 0

    with (root / ".claim.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        now = time.time()
        candidates = []
        for bundle in root.iterdir():
            if not bundle.is_dir():
                continue
            if not (bundle / ".ready").exists():
                continue
            if (bundle / ".posted").exists():
                continue
            if (out / f"{bundle.name}.json").exists():
                continue
            claim = bundle / ".claim"
            if claim.exists():
                try:
                    if now - claim.stat().st_mtime < args.claim_ttl:
                        continue
                except FileNotFoundError:
                    pass
                claim.unlink(missing_ok=True)
            try:
                candidates.append((bundle.stat().st_mtime, bundle.name, bundle))
            except FileNotFoundError:
                continue

        if not candidates:
            print("NO_CLAIM")
            return 0

        candidates.sort()
        _, name, bundle = candidates[0]
        (bundle / ".claim").write_text(f"{args.worker} {int(now)}\n")
        print(f"CLAIM {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
