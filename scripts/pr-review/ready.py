#!/usr/bin/env python3
"""Print the review bundles that are ready for the agent. Stable output."""

from __future__ import annotations

import os
from pathlib import Path


def main() -> int:
    root = Path(os.environ.get("HERMES_REVIEW_IN", "/opt/data/review-in"))
    out = Path(os.environ.get("HERMES_REVIEW_OUT", "/opt/data/review-out"))
    ready = []
    if root.is_dir():
        for bundle in sorted(root.iterdir()):
            if not bundle.is_dir():
                continue
            if not (bundle / ".ready").exists():
                continue
            if (bundle / ".posted").exists():
                continue
            if (out / f"{bundle.name}.json").exists():
                continue
            ready.append(bundle.name)
    print("\n".join(f"READY {name}" for name in ready) or "NO_READY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
