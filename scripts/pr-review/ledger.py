#!/usr/bin/env python3
"""SQLite ledger for PR review work.

One row per ``(repo, pr, head)``. The ledger is the queue, the lease table, and
the record of what was already published. Bundle directories stay the payload;
this file only decides who owns a head and what happened to it.

A claim is a short lease on a row. Expired leases may be taken over, so a dead
worker cannot block a head for an hour. After ``max_attempts`` expired leases
the row is failed instead of retried forever.
"""

from __future__ import annotations

import sqlite3
import time
from pathlib import Path

STATES = ("queued", "leased", "published", "stale", "failed")

SCHEMA = """
CREATE TABLE IF NOT EXISTS reviews (
    repo         TEXT    NOT NULL,
    pr           INTEGER NOT NULL,
    head         TEXT    NOT NULL,
    base         TEXT    NOT NULL DEFAULT '',
    bundle       TEXT    NOT NULL DEFAULT '',
    state        TEXT    NOT NULL DEFAULT 'queued',
    attempts     INTEGER NOT NULL DEFAULT 0,
    lease_owner  TEXT,
    lease_expires REAL,
    requested_at REAL    NOT NULL,
    updated_at   REAL    NOT NULL,
    error        TEXT,
    PRIMARY KEY (repo, pr, head)
);
CREATE INDEX IF NOT EXISTS reviews_claimable
    ON reviews(state, lease_expires, requested_at);
"""


def connect(path: str | Path) -> sqlite3.Connection:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=10, isolation_level=None)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA busy_timeout=10000")
    db.executescript(SCHEMA)
    return db


def record(
    db: sqlite3.Connection,
    repo: str,
    pr: int,
    head: str,
    base: str,
    bundle: str,
) -> None:
    """Queue a head. Published, stale and failed rows are never resurrected."""
    now = time.time()
    db.execute(
        """
        INSERT INTO reviews (repo, pr, head, base, bundle, state, requested_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'queued', ?, ?)
        ON CONFLICT(repo, pr, head) DO UPDATE SET
            base = excluded.base,
            bundle = excluded.bundle,
            updated_at = excluded.updated_at
        WHERE reviews.state = 'queued'
        """,
        (repo, pr, head, base, bundle, now, now),
    )


def get(
    db: sqlite3.Connection, repo: str, pr: int, head: str
) -> sqlite3.Row | None:
    return db.execute(
        "SELECT * FROM reviews WHERE repo = ? AND pr = ? AND head = ?",
        (repo, pr, head),
    ).fetchone()


def get_bundle(db: sqlite3.Connection, bundle: str) -> sqlite3.Row | None:
    return db.execute(
        "SELECT * FROM reviews WHERE bundle = ? ORDER BY updated_at DESC LIMIT 1",
        (bundle,),
    ).fetchone()


def finish(
    db: sqlite3.Connection,
    repo: str,
    pr: int,
    head: str,
    state: str,
    error: str | None = None,
) -> None:
    if state not in STATES:
        raise ValueError(f"unknown ledger state: {state}")
    db.execute(
        """
        UPDATE reviews
        SET state = ?, lease_owner = NULL, lease_expires = NULL,
            updated_at = ?, error = ?
        WHERE repo = ? AND pr = ? AND head = ? AND state != 'published'
        """,
        (state, time.time(), error, repo, pr, head),
    )


def finish_bundle(
    db: sqlite3.Connection, bundle: str, state: str, error: str | None = None
) -> None:
    row = get_bundle(db, bundle)
    if row is not None:
        finish(db, row["repo"], row["pr"], row["head"], state, error)


def supersede(
    db: sqlite3.Connection, repo: str, pr: int, head: str
) -> None:
    """Drop queued or expired work for older heads of the same PR."""
    now = time.time()
    db.execute(
        """
        UPDATE reviews
        SET state = 'stale', lease_owner = NULL, lease_expires = NULL,
            updated_at = ?, error = 'superseded by a newer head'
        WHERE repo = ? AND pr = ? AND head != ?
          AND (state = 'queued'
               OR (state = 'leased' AND lease_expires < ?)
               OR state = 'failed')
        """,
        (now, repo, pr, head, now),
    )


def requeue(db: sqlite3.Connection, repo: str, pr: int, head: str) -> None:
    """Return a failed or staled head to the queue with a fresh attempt budget.

    A valid packet that exhausted its attempts, or a head staled by a closed
    PR or a misread open-PR list, must be reviewable again at the same commit.
    """
    db.execute(
        """
        UPDATE reviews
        SET state = 'queued', attempts = 0, lease_owner = NULL,
            lease_expires = NULL, updated_at = ?, error = NULL
        WHERE repo = ? AND pr = ? AND head = ?
          AND state IN ('failed', 'stale', 'published')
        """,
        (time.time(), repo, pr, head),
    )


def claim(
    db: sqlite3.Connection,
    worker: str,
    ttl: int,
    max_attempts: int = 3,
) -> sqlite3.Row | None:
    """Lease the oldest claimable row, atomically across processes."""
    now = time.time()
    db.execute("BEGIN IMMEDIATE")
    try:
        while True:
            row = db.execute(
                """
                SELECT * FROM reviews
                WHERE state = 'queued'
                   OR (state = 'leased' AND lease_expires < ?)
                ORDER BY requested_at, rowid
                LIMIT 1
                """,
                (now,),
            ).fetchone()
            if row is None:
                db.execute("COMMIT")
                return None
            if row["attempts"] >= max_attempts:
                db.execute(
                    """
                    UPDATE reviews
                    SET state = 'failed', lease_owner = NULL, lease_expires = NULL,
                        updated_at = ?, error = 'lease expired after max attempts'
                    WHERE repo = ? AND pr = ? AND head = ?
                    """,
                    (now, row["repo"], row["pr"], row["head"]),
                )
                continue
            db.execute(
                """
                UPDATE reviews
                SET state = 'leased', lease_owner = ?, lease_expires = ?,
                    attempts = attempts + 1, updated_at = ?
                WHERE repo = ? AND pr = ? AND head = ?
                """,
                (worker, now + ttl, now, row["repo"], row["pr"], row["head"]),
            )
            row = get(db, row["repo"], row["pr"], row["head"])
            db.execute("COMMIT")
            return row
    except Exception:
        db.execute("ROLLBACK")
        raise


def has_claimable(db: sqlite3.Connection) -> bool:
    now = time.time()
    return (
        db.execute(
            """
            SELECT 1 FROM reviews
            WHERE state = 'queued'
               OR (state = 'leased' AND lease_expires < ?)
            LIMIT 1
            """,
            (now,),
        ).fetchone()
        is not None
    )


def claimable_count(db: sqlite3.Connection) -> int:
    now = time.time()
    return db.execute(
        """
        SELECT COUNT(*) FROM reviews
        WHERE state = 'queued'
           OR (state = 'leased' AND lease_expires < ?)
        """,
        (now,),
    ).fetchone()[0]


def count(db: sqlite3.Connection) -> int:
    return db.execute("SELECT COUNT(*) FROM reviews").fetchone()[0]
