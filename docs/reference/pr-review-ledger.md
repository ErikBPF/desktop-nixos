# PR review ledger and dispatch

**Status:** Implemented and live on `discovery` (2026-10-30).

Hackerman reviews Erik's pull requests from host-collected bundles. The host
collector owns GitHub credentials; the agent only reads a bundle and writes
review JSON. This document records the queue contract: the SQLite ledger, its
leases, and how new heads dispatch workers.

## Flow

1. `hermes-pr-review-collect.timer` runs every 2 minutes.
2. The collector lists open PRs, writes one immutable bundle per new
   `(repo, pr, head)` under `review-in/`, and queues a ledger row.
3. If any row is claimable, the collector's `ExecStartPost` runs
   `hermes-pr-review-dispatch`.
4. Dispatch starts up to `parallelism` transient `systemd-run` units, one per
   claimable row (`hermes cron run hermes-pr-review-N`). Each worker's claim
   script leases exactly one row.
5. The agent writes `review-out/<bundle>.json`.
6. `hermes-pr-review-publish.timer` runs every 2 minutes, posts the comment,
   review verdict, and gate check, writes a root-only publication marker under
   `/var/lib/hermes-pr-review/published/`, then marks the row `published`.

A new head is normally visible as a check within review time plus about four
minutes. Workers still have their own 10-minute cron fallback; dispatch just
removes the wait for the next shared tick.

## Ledger

Path: `review-ledger/ledger.db` under the Hermes data dir (container:
`/opt/data/review-ledger/ledger.db`). One row per commit, not per PR.

```sql
reviews(
  repo, pr, head, base, bundle,
  state, attempts, lease_owner, lease_expires,
  requested_at, updated_at, error,
  PRIMARY KEY (repo, pr, head)
)
```

States:

| State | Meaning |
|---|---|
| `queued` | Not leased. Claimable. |
| `leased` | A worker owns the head until `lease_expires`. |
| `published` | Comment, review, and check were posted. Never re-reviewed. |
| `stale` | Superseded head, closed PR, or a bundle that no longer exists. |
| `failed` | Invalid packet or lease expired after `max_attempts`. |

Leases are 30 minutes. An expired lease is claimable again, so a dead worker
does not block the head for the old one-hour file-claim TTL. After three
expired leases an open head becomes `failed`; the collector retries it after
45 minutes with a fresh attempt budget. A `stale` head that is still open at
the same commit is revived on the next collect.

`published` needs both the ledger row and the root-only marker
`/var/lib/hermes-pr-review/published/<head>.json` whose recorded head matches
the row. The marker directory is not mounted into the agent container, so a
forged ledger state alone cannot silence the gate. The publisher also rejects a
packet whose bundle name does not match the packet's repo, PR and head.

`claim.py` leases atomically with `BEGIN IMMEDIATE`. File claims under
`review-claims/` are no longer used.

## Operations

Inspect the queue on `discovery`:

```bash
sudo sqlite3 /home/erik/homelab/apps/hermes-daedalus/review-ledger/ledger.db \
  "select state, count(*) from reviews group by state;"
```

Force a collect and dispatch now:

```bash
sudo systemctl start hermes-pr-review-collect.service
```

Inspect workers and dispatches:

```bash
systemctl list-units 'hermes-pr-review-trigger*'   # in-flight only
journalctl -u 'hermes-pr-review-trigger*' --since '-15 min'
docker exec hermes-daedalus /opt/hermes/.venv/bin/hermes cron list
```

Publish promptly without waiting for the timer:

```bash
sudo systemctl start hermes-pr-review-publish.service
```

## Failure handling

- Missing bundle: the claim loop marks the row `stale` and tries the next row;
  it does not burn the worker's turn.
- Invalid review JSON: publish marks it `failed` and moves the packet to
  `review-stale/`.
- Head moved or PR merged before publish: publish marks the row `stale` and
  discards the packet.
- Closed or merged PRs: the next collect marks any queued, failed, or expired
  leased head `stale`, so merged heads are not retried.
- A `published` row without a matching root-only marker (forged or lost state)
  is requeued and reviewed again.
- Collector errors are per repository and do not stop the other repositories.

## Migration and rollback

The first collector run after activation imports the old
`/var/lib/hermes-pr-review/state.json` once. Published heads become
`published`; requested heads are imported only when their bundle still exists.
The ledger is a cache of queue state, not review content; bundles and published
packets remain the audit trail.

Rollback is the previous NixOS generation. A generation rollback leaves the
ledger and marker files in place; the old code ignores them, but it reads the
frozen `/var/lib/hermes-pr-review/state.json`. Heads published after the
migration are absent from that file, so the old collector rebuilds and
re-reviews them. Prefer keeping the new generation; if rollback is required,
expect re-review churn for post-migration heads.
