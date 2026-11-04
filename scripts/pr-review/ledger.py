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

import re
import sqlite3
import time
from pathlib import Path

STATES = ("queued", "leased", "published", "stale", "failed", "reusing")
HEAD_RE = re.compile(r"\A[0-9a-f]{7,64}\Z")

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
    diff_hash    TEXT    NOT NULL DEFAULT '',
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
    columns = {row["name"] for row in db.execute("PRAGMA table_info(reviews)")}
    if "diff_hash" not in columns:
        db.execute(
            "ALTER TABLE reviews ADD COLUMN diff_hash TEXT NOT NULL DEFAULT ''"
        )
    return db


def record(
    db: sqlite3.Connection,
    repo: str,
    pr: int,
    head: str,
    base: str,
    bundle: str,
    diff_hash: str = "",
) -> None:
    """Queue a head. Published, stale and failed rows are never resurrected."""
    now = time.time()
    db.execute(
        """
        INSERT INTO reviews
            (repo, pr, head, base, bundle, state, requested_at, updated_at, diff_hash)
        VALUES (?, ?, ?, ?, ?, 'queued', ?, ?, ?)
        ON CONFLICT(repo, pr, head) DO UPDATE SET
            base = excluded.base,
            bundle = excluded.bundle,
            updated_at = excluded.updated_at,
            diff_hash = excluded.diff_hash
        WHERE reviews.state = 'queued'
        """,
        (repo, pr, head, base, bundle, now, now, diff_hash),
    )


def get(
    db: sqlite3.Connection, repo: str, pr: int, head: str
) -> sqlite3.Row | None:
    return db.execute(
        "SELECT * FROM reviews WHERE repo = ? AND pr = ? AND head = ?",
        (repo, pr, head),
    ).fetchone()


def bundle_id(repo: str, pr: int, head: str) -> str:
    owner, name = repo.split("/", 1)
    return f"{owner}__{name}__{pr}__{head[:12]}"


def valid_bundle(row) -> bool:
    """True when a ledger row's bundle and head are safe to turn into a path.

    The ledger is writable by the reviewing agent, and the collector and
    request tool delete paths as root. A row may therefore name a bundle only
    when it is exactly the name this repo, PR and head produce.
    """
    try:
        head = str(row["head"] or "")
        repo = str(row["repo"] or "")
        pr = int(row["pr"])
        bundle = str(row["bundle"] or "")
    except (KeyError, IndexError, TypeError, ValueError):
        return False
    if not HEAD_RE.fullmatch(head):
        return False
    try:
        expected = bundle_id(repo, pr, head)
    except ValueError:
        return False
    return bundle == expected


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
    ``reusing`` is included so a lost reuse packet falls back to a real review.
    """
    # A revival is a new request. Without this, has_newer_head keeps staling a
    # current head against a published sibling after a force-push back.
    now = time.time()
    db.execute(
        """
        UPDATE reviews
        SET state = 'queued', attempts = 0, lease_owner = NULL,
            lease_expires = NULL, requested_at = ?, updated_at = ?, error = NULL
        WHERE repo = ? AND pr = ? AND head = ?
          AND state IN ('failed', 'stale', 'published', 'reusing')
        """,
        (now, now, repo, pr, head),
    )


def last_published(
    db: sqlite3.Connection, repo: str, pr: int
) -> sqlite3.Row | None:
    """Newest published head for this PR that recorded a diff hash."""
    return db.execute(
        """
        SELECT * FROM reviews
        WHERE repo = ? AND pr = ? AND state = 'published' AND diff_hash != ''
        ORDER BY updated_at DESC, rowid DESC
        LIMIT 1
        """,
        (repo, pr),
    ).fetchone()


def mark_reusing(
    db: sqlite3.Connection,
    repo: str,
    pr: int,
    head: str,
    base: str,
    bundle: str,
    diff_hash: str,
) -> None:
    """Queue a publisher-only row whose review packet was copied from a prior head.

    ``reusing`` is deliberately absent from every claim query: dispatch must not
    spend a worker on a head whose diff already has a verdict.
    """
    now = time.time()
    db.execute(
        """
        INSERT INTO reviews
            (repo, pr, head, base, bundle, state, requested_at, updated_at, diff_hash)
        VALUES (?, ?, ?, ?, ?, 'reusing', ?, ?, ?)
        ON CONFLICT(repo, pr, head) DO UPDATE SET
            base = excluded.base,
            bundle = excluded.bundle,
            state = 'reusing',
            attempts = 0,
            lease_owner = NULL,
            lease_expires = NULL,
            updated_at = excluded.updated_at,
            error = NULL,
            diff_hash = excluded.diff_hash
        WHERE reviews.state IN ('queued', 'failed', 'stale')
        """,
        (repo, pr, head, base, bundle, now, now, diff_hash),
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


def has_newer_head(
    db: sqlite3.Connection, repo: str, pr: int, head: str, requested_at: float
) -> bool:
    """True when a later-requested head for the same PR is still live.

    A worker that claimed an older head would spend a full review on a commit
    the publisher will reject as stale. Skip it before reading the bundle.
    """
    return (
        db.execute(
            """
            SELECT 1 FROM reviews
            WHERE repo = ? AND pr = ? AND head != ? AND requested_at > ?
              AND state IN ('queued', 'leased', 'published')
            LIMIT 1
            """,
            (repo, pr, head, requested_at),
        ).fetchone()
        is not None
    )


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
