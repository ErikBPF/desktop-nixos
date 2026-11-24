#!/usr/bin/env python3
"""Publish the review queue as node-exporter textfile metrics.

"Is Hackerman throttling?" was answered by hand from the ledger, the Hermes
execution table and the LiteLLM spend log. These are the four numbers that
answered it, refreshed by a timer: queue depth, oldest wait, throughput, and
the Hermes execution outcomes per source (a `direct` run colliding with the
ticker used to look like a failure).

Read-only: both databases are opened with ``mode=ro`` so a scrape can never
block a claim. Absent files emit nothing rather than a false zero.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import ledger

FIFTEEN_MINUTES = 900
HOUR = 3600


def connect_ro(path: Path) -> sqlite3.Connection | None:
    if not path.is_file():
        return None
    uri = f"file:{path}?mode=ro"
    db = sqlite3.connect(uri, uri=True, timeout=2)
    db.row_factory = sqlite3.Row
    return db


def one(db, query: str, params: tuple = ()) -> int:
    row = db.execute(query, params).fetchone()
    return int(row[0] or 0) if row is not None else 0


def ledger_metrics(db, lines: list[str]) -> None:
    now = time.time()
    lines.append("# HELP hermes_pr_review_queue_depth Heads by ledger state.")
    lines.append("# TYPE hermes_pr_review_queue_depth gauge")
    for state in ("queued", "leased", "published", "stale", "failed", "reusing"):
        lines.append(
            f'hermes_pr_review_queue_depth{{state="{state}"}} '
            f'{one(db, "SELECT COUNT(*) FROM reviews WHERE state = ?", (state,))}'
        )
    # What the workers act on: never-claimed rows plus leases a dead worker left.
    lines.append(
        f'hermes_pr_review_queue_depth{{state="claimable"}} '
        f'{ledger.claimable_count(db)}'
    )
    oldest = db.execute(
        "SELECT MIN(requested_at) FROM reviews "
        "WHERE state = 'queued' OR (state = 'leased' AND lease_expires < ?)",
        (now,),
    ).fetchone()[0]
    age = 0 if oldest is None else int(max(0, now - float(oldest)))
    lines.append("# HELP hermes_pr_review_oldest_wait_seconds Age of the oldest claimable head.")
    lines.append("# TYPE hermes_pr_review_oldest_wait_seconds gauge")
    lines.append(f"hermes_pr_review_oldest_wait_seconds {age}")
    lines.append("# HELP hermes_pr_review_published Reviews published in the window.")
    lines.append("# TYPE hermes_pr_review_published gauge")
    for window, seconds in (
        ("15m", FIFTEEN_MINUTES),
        ("1h", HOUR),
        ("24h", 24 * HOUR),
    ):
        count = one(
            db,
            "SELECT COUNT(*) FROM reviews "
            "WHERE state = 'published' AND updated_at > ?",
            (now - seconds,),
        )
        lines.append(f'hermes_pr_review_published{{window="{window}"}} {count}')
    latency = db.execute(
        "SELECT AVG(updated_at - requested_at) FROM reviews "
        "WHERE state = 'published' AND updated_at > ?",
        (now - 24 * HOUR,),
    ).fetchone()[0]
    lines.append("# HELP hermes_pr_review_latency_seconds Mean request-to-publish, 24h.")
    lines.append("# TYPE hermes_pr_review_latency_seconds gauge")
    lines.append(
        f"hermes_pr_review_latency_seconds {round(float(latency or 0.0), 1)}"
    )


def execution_metrics(db, lines: list[str]) -> None:
    lines.append("# HELP hermes_pr_review_executions Hermes cron executions, 24h.")
    lines.append("# TYPE hermes_pr_review_executions gauge")
    cutoff = (
        datetime.now(timezone.utc) - timedelta(days=1)
    ).isoformat(timespec="microseconds")
    rows = db.execute(
        "SELECT source, status, COUNT(*) FROM executions "
        "WHERE claimed_at > ? GROUP BY source, status",
        (cutoff,),
    ).fetchall()
    for row in rows:
        lines.append(
            f'hermes_pr_review_executions{{source="{row[0]}",status="{row[1]}"}} {row[2]}'
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--ledger", default=None)
    parser.add_argument("--executions", default=None)
    parser.add_argument(
        "--textfile-dir", default="/var/lib/node-exporter-textfile"
    )
    parser.add_argument("--name", default="hermes-pr-review.prom")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    ledger_path = Path(
        args.ledger or data_dir / "review-ledger" / "ledger.db"
    )
    lines: list[str] = []

    db = connect_ro(ledger_path)
    if db is None:
        print(f"missing ledger: {ledger_path}", file=sys.stderr)
        return 0
    try:
        ledger_metrics(db, lines)
    except sqlite3.Error as exc:
        # A checkpoint in flight can hold the WAL. Skip this scrape and let the
        # next one report, rather than failing the unit and blanking the panel.
        print(f"ledger metrics unavailable: {exc}", file=sys.stderr)
    finally:
        db.close()

    db = connect_ro(Path(args.executions or data_dir / "cron" / "executions.db"))
    if db is not None:
        try:
            execution_metrics(db, lines)
        except sqlite3.Error as exc:
            print(f"execution metrics unavailable: {exc}", file=sys.stderr)
        finally:
            db.close()

    out_dir = Path(args.textfile_dir)
    if not out_dir.is_dir():
        print(f"missing textfile dir: {out_dir}", file=sys.stderr)
        return 0
    tmp = out_dir / f".{args.name}.{os.getpid()}"
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(out_dir / args.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
