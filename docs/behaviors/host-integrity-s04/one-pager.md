# S04: staged Endeavour pilot source

**Status:** Reviewed source preparation; no live activation or observation claimed here.

## Outcome and why

The pilot can introduce collection before jobs, prove enrolled identity before
scanning, and perform controlled synthetic detection/recovery without erasing a
real finding or claiming complete Downloads coverage. The user approved only
`/home/erik/Downloads` for mutable-file AV. Existing oversized/symlink exclusions
remain visible as partial coverage. The seven-day observation clock starts only
after real schedules activate; local tests cannot complete that evidence.

## Changes

An Endeavour aspect defaults to collector-only: three checks, no jobs or timers.
Separate `enableJobs` and `enableSchedules` options make manual-job and scheduled
stages explicit reviewed revisions. Budgets bound CPU, memory, deadlines, copy
size, traversal and output. Receipts retain 30 days and at most 128 per check.
Other hosts remain unenrolled.

Operator recipes provide status, sequential starts, a read-only Nix daemon probe
inside the actual store sandbox, synthetic AV cases inside the actual AV sandbox,
reviewed resolution and exact known-good rollback. Resolution requires root,
the current state digest, locked private state and matching synthetic/recovery
receipts. It changes only findings and publication time. Partial coverage and
prior completion remain unchanged; no automatic or real-finding clear exists.

Review exposed a crash gap where a genuine observation could share the synthetic
high-water count without a final receipt. The reporter now durably records unique
genuine provenance before publishing positive counts. Any genuine marker blocks
both synthetic canaries and their resolution, including a marker persisted just
before a crash that prevented counter publication. No timestamp comparison can
permit clearing that marker.

Review also exposed scheduled work bypassing a shell-only backup guard. Each
actual Restic invocation now shares a root-private exclusion lock with the
integrity runner and canaries when jobs activate. Scans refuse a busy lock;
Restic waits at most 1860 seconds and surfaces timeout. Backup services can be
active while waiting/preparing; protected data operations do not overlap. The
collector-only stage leaves the existing backup package unchanged.

## Evidence and limits

Six initial behavior assertions failed against a new no-op seam before helper
implementation. Subsequent assertions reproduced lost-receipt genuine clearing,
pre-counter-publication crash ambiguity and backup overlap in both directions;
repairs retained explicit RED/GREEN evidence. The focused helper/reporter/runner
suite passed 66 tests independently; final CI-mode helper/collector/Alloy validation
passed 70 tests. Actual pinned ClamAV
runs used temporary harmless fixtures and a tiny local signature database,
never host content or production definitions.

The staged Nix fixture checks collector/manual/scheduled behavior, Downloads-only
scope, finite budgets, shared sandbox properties, explicit daemon access and the
actual backup wrapper/lock path. An earlier fixture edit failed to insert its
new assertions because the final marker shared an assertion line; that limited
evaluation was not proof of the omitted checks. The corrected fixture passed
locally and independently. Lint, format, structure, documentation, S01/S02/S04
evaluations and Endeavour offline dry-run passed. Fresh review found no remaining
material source blocker. Exact results are recorded in the [test contract](test-contract.md).

The precommit candidate remains unrealized; its dry-run lists 2256 derivations
to build. This does not establish a pilot-only activation diff. The published
revision must be re-evaluated, built and compared against the running closure
before switching. Commit `342a74f0` passed its actual hooks; no hook bypass or
live host activation occurred in this source-validation pass.

## Decisions, remaining work and recovery

The [owner runbook](../../reference/host-integrity-pilot.md) records exact commands,
armed single-check restoration and generation-211 rollback. The coordinating
agent must inspect the candidate/current closure diff before switching, publish
compatible enrollment revisions, capture actual firing/resolved receipts and
observe seven days. The pre-existing home-backup failure remains qualified,
unrepaired baseline evidence. No unrelated upgrades, backup reset, host outage,
quarantine or fleet rollout are authorized by this source change.
