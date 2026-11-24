# PR review ledger, schedule and queue metrics

**Status:** Implemented and live on `discovery` (2026-10-30). Trigger filters,
draft policy, unchanged-diff reuse, and the local request tool are deployed.
The ticker-owned schedule, settle window, delta reviews, bundle retention, WAL
ledger and queue metrics are in source and await deployment.

Hackerman reviews Erik's pull requests from host-collected bundles. The host
collector owns GitHub credentials; the agent only reads a bundle and writes
review JSON. This document records the queue contract: the SQLite ledger, its
leases, and how new heads dispatch workers.

## Flow

1. `hermes-pr-review-collect.timer` runs every 2 minutes.
2. The collector lists open PRs, skips what the repository's filters exclude
   (ignored author, label, or title) and, when `reviewDrafts` is false, draft
   PRs, then writes one immutable bundle per new `(repo, pr, head)` under
   `review-in/` and queues a ledger row. A filtered head gets a `neutral`
   `hackerman-cr/evaluation` check so the required check still passes; an
   existing run for that head is never overwritten. Drafts get no check until
   they are reviewed, because a draft is not mergeable. Bundles are created under `umask 022`
   and hardened again before the rename, so the reviewing agent cannot rewrite
   its own diff or evidence.
   A head the ledger has never seen waits for the settle window
   (`settleMinutes`, default 5): the collector remembers the head it saw on the
   previous pass and bundles it only once the head has been stable that long.
   A branch that lands three commits in five minutes then costs one review, not
   three, of a head nobody looks at. `settleMinutes = 0` reviews every head
   immediately; the cost is the missing required check until the review lands.
   A new head whose diff hash equals the newest published head of the same PR
   reuses that verdict: the collector copies the published bundle and packet,
   refetches `docs/` and `skills/` at the new base, updates the head, and
   queues a `reusing` row. The publisher still posts the comment and the
   required check for the new head, but no worker runs the model. Reuse
   requires both the diff and the base-pinned guidance to match byte for byte;
   a rebase that changed contributor guidance or review skills goes through a
   real review instead.

   A head that differs from the newest published head of its PR also gets
   `delta.patch`: the GitHub comparison `previous_head...head`, written in the
   bundle beside the full `diff.patch`. The worker reviews the delta and carries
   the still-open findings forward, which is where most of the model spend went
   — two thirds of all bundles are a second or later head of a PR that already
   has a published review. The delta is withheld (full diff reviewed instead)
   whenever it cannot be trusted: a force-push (`status` not
   `ahead`), a comparison at the 300-file ceiling, or a file whose patch GitHub
   omitted. Evidence validation accepts a quote from either patch. The bundle
   also carries `previous-review.json`, the published review JSON of that
   earlier head: the publisher renders its packet into a PR comment, so the
   finding text and the stable ids exist only there, and a worker cannot carry
   an open finding forward without them.

   This depends on the `cr-pr` worker skill accepting `delta.patch`. The skill
   ships from `hermes-skills`, not from this repository, and
   `bootstrap-cron.sh` refuses to run without it: deploy the skill first
   (`just sync-hermes-skills discovery`), because a worker running the older
   skill treats a delta quote as unverifiable evidence and discards the
   finding. Until the skill is deployed, the collector's `delta.patch` only
   saves the worker a re-read; the full diff is still in the bundle.

   Finished bundles accumulate in `review-done/`. The collector keeps
   `retainBundles` heads per repository (default 20) plus the newest published
   head of every PR, which is what verdict reuse reads; older directories and
   their packets are deleted. `0` keeps everything.

   For a repository listed in `ocrRepos`, the collector also runs the Open Code
   Review candidate pass before the bundle is sealed. It fetches base and head
   into a per-repository bare cache under `repo-cache/`, adds a detached
   worktree, and writes `ocr.json` into the bundle. That file holds a candidate
   list, or `{"status":"error"}` when the pass fails. Candidates are advisory:
   the worker keeps the verdict and must re-quote evidence from the diff. The
   pass reads `/run/vault-agent/hermes-ocr.env`, rendered from
   `secret/home/ocr-review-litellm`, and it is fail-open — a missing credential
   or a failed run leaves the bundle reviewable without candidates. One head is
   bounded by `ocrTimeoutMinutes` times the effort rounds (low 1, medium 2,
   high 3), clamped to what remains of a 20-minute OCR budget per collect run
   after a fixed fetch/worktree reserve; heads admitted without enough budget
   left get `{"status":"skipped"}`. The collect unit keeps a 30-minute start
   bound.
3. Each worker job carries the `schedule` (default `*/2 * * * *`) on the
   Hermes cron ticker. The ticker starts up to `parallelism`
   of them when they are due, and each worker's claim script leases exactly one
   row. There is no host-side dispatcher: an out-of-band `hermes cron run` for
   a job the ticker already fired loses the fire claim, so the ticker recorded
   the execution as failed (80 such rows in two days) while the review itself
   ran fine. The failure count was the whole visible "throttle".

   The `hermes-pr-review-dispatch` unit and its `systemd-run` workers were
   removed for that reason. Pickup latency is now the tick
   interval, not "immediately after collect" — up to two minutes on top of a
   review that averages six.
4. The agent writes `review-out/<bundle>.json`.
6. `hermes-pr-review-publish.timer` runs every 30 seconds, posts the comment,
   review verdict, and gate check, writes a root-only publication marker under
   `/var/lib/hermes-pr-review/published/`, then marks the row `published`.

A new head is normally visible as a check within the settle window plus review
time plus about one minute. An OCR-enabled deployment adds the serial candidate
pass — up to
`ocrTimeoutMinutes` × effort rounds per new head, capped at 20 minutes of OCR
work per collect run — before the bundle is sealed. The collect unit carries a
30-minute start bound for that reason. An idle worker prints the Hermes
`{"wakeAgent": false}` gate and exits without invoking the model.

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
| `published` | Comment, review, and check were posted. Never re-reviewed on its own. |
| `reusing` | Copied verdict awaiting publish; never claimable by a worker. |
| `stale` | Superseded head, closed PR, or a bundle that no longer exists. |
| `failed` | Invalid packet or lease expired after `max_attempts`. |

Leases are 30 minutes. An expired lease is claimable again, so a dead worker
does not block the head for the old one-hour file-claim TTL. After three
expired leases an open head becomes `failed`; the collector retries it after
45 minutes with a fresh attempt budget. A `stale` head that is still open at
the same commit is revived on the next collect.

`published` needs both the ledger row and the root-only marker
`/var/lib/hermes-pr-review/published/<head>.json` whose recorded head matches
the row. The directory is mode `0700` and each marker `0600`; it is not mounted
into the agent container, so a forged ledger state alone cannot silence the
gate. The publisher also rejects a packet whose bundle name does not match the
packet's repo, PR and head.

The ledger database is writable by the reviewing agent, so its strings are
never used as paths. A row's bundle is accepted only when it equals
`<owner>__<name>__<pr>__<head[:12]>` and the head is hexadecimal; otherwise the
claim loop, the collector's reuse recovery, and `hermes-pr-review-request` mark
the row failed and touch nothing. The same check gates the `review-done/` copy
that reuse reads from.

`claim.py` leases atomically with `BEGIN IMMEDIATE`. Before reviewing, it marks
the claimed head `stale` when a newer head for the same PR is queued, leased, or
published, so a fast push does not spend a worker on an obsolete commit. An
idle worker prints `{"wakeAgent": false}` as its last stdout line, which Hermes
uses to skip the agent run entirely. File claims under `review-claims/` are no
longer used.

The database runs in WAL mode with `synchronous=NORMAL`. Five workers claim
while the collector inserts and the publisher updates, and rollback-journal
mode surfaced that contention as `sqlite3.OperationalError: database is
locked` in the publisher. WAL lets readers proceed behind a writer; the
`busy_timeout` remains as a backstop.

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

Inspect workers:

```bash
docker exec hermes-daedalus /opt/hermes/.venv/bin/hermes cron list

```

The queue is exported as textfile metrics every minute
(`/var/lib/node-exporter-textfile/hermes-pr-review.prom`), so "are the workers
throttled?" is a query, not an investigation:

```bash
curl -s localhost:9100/metrics | grep hermes_pr_review_
```

| Metric | Question it answers |
|---|---|
| `hermes_pr_review_queue_depth{state}` | Is work waiting, and in which state? `claimable` is what dispatch acts on. |
| `hermes_pr_review_oldest_wait_seconds` | How long has the oldest claimable head waited? |
| `hermes_pr_review_published{window}` | Throughput over 15m, 1h and 24h. Compare with `parallelism` ÷ mean review time. |
| `hermes_pr_review_latency_seconds` | Mean request-to-publish over 24h. |
| `hermes_pr_review_executions{source,status}` | Hermes execution outcomes. `source="builtin"` is the ticker; failed rows here are what used to look like throttling. Hermes keeps only the newest 1 000 terminal rows, so read `hermes_pr_review_executions_window_seconds` for the span these counts cover — hours, not a day. |

Publish promptly without waiting for the timer:

```bash
sudo systemctl start hermes-pr-review-publish.service
```

Request a fresh review of one head from the workstation (`gh` auth reads the
live head; no bot credential is involved):

```bash
just pr-review-request ErikBPF/aster 42
```

That recipe runs `hermes-pr-review-request` on `discovery`, which requeues a
published, stale, or failed head, clears that head's old publication marker,
and starts the collector. It then waits for the marker to reappear and prints
the review URL. Clearing the marker matters: it is keyed by head, so a waiter
would otherwise read the previous verdict as this request's result. This is the
local replacement for a GitHub comment command; the bot has no inbound webhook
and no comment trigger.

## Failure handling

- Missing bundle: the claim loop marks the row `stale` and tries the next row;
  it does not burn the worker's turn.
- Superseded head: the claim loop marks the older head `stale` and tries the
  newer head before starting a review.
- Invalid review JSON: publish marks it `failed` and moves the packet to
  `review-stale/`.
- Head moved or PR merged before publish: publish marks the row `stale` and
  discards the packet.
- Closed or merged PRs: the next collect marks any queued, failed, or expired
  leased head `stale`, so merged heads are not retried.
- A `published` row without a matching root-only marker (forged or lost state)
  is requeued and reviewed again.
- A `reusing` row whose copied packet is missing is requeued and reviewed for
  real; its bundle is discarded first.
- A reuse candidate whose guidance at the new base differs from the copied
  bundle is reviewed for real, not published with the old verdict.
- A delta that cannot be trusted (force-push, truncated comparison, omitted
  file patch, GitHub error) falls back to the full diff; the collector logs a
  warning for the error case only.
- A head that never settles (a branch pushing more often than the settle
  window) is reviewed at the head that survives; `SETTLE <repo>#<pr>` lines in
  the collect log show each deferral.
- A malformed `settle.json` is treated as empty, so the worst case is one extra
  settle window, never a stuck head.
- An on-demand request clears the head's publication marker before the
  collector runs, so the recipe cannot report the previous verdict. A request
  for a head the ledger has never seen also marks it settled, so the next
  collect bundles it instead of waiting out the settle window.
- An ignored head is never bundled. An existing `queued` or `published` row is
  not revoked by a later filter match. The neutral skip check is posted once;
  a check-run API error is reported and retried on the next collect.
- An invalid `ignoreTitle` pattern is reported on stderr and ignored, so a
  typo cannot silently stop reviews.
- Collector errors are per repository and do not stop the other repositories.

## Migration and rollback

The first collector run after activation imports the old
`/var/lib/hermes-pr-review/state.json` once. Published heads become
`published`; requested heads are imported only when their bundle still exists.
Legacy bundle-named publication markers are renamed to their recorded head.
The ledger is a cache of queue state, not review content; bundles and published
packets remain the audit trail.

Rollback is the previous NixOS generation. A generation rollback leaves the
ledger and marker files in place; the old code ignores them, but it reads the
frozen `/var/lib/hermes-pr-review/state.json`. Heads published after the
migration are absent from that file, so the old collector rebuilds and
re-reviews them. Prefer keeping the new generation; if rollback is required,
expect re-review churn for post-migration heads.
