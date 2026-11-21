# S02: bounded integrity jobs, reviewed implementation

## Outcome and why

Three independent jobs turn S01's reporting boundary into explicit signature,
store-content and AV work. A successful updater is not fresh definitions; a
scheduled scan is not complete coverage; a process timeout must not erase an
already observed finding. The runner preserves those distinctions. Handled tool failures can leave the systemd unit successful; metric state and
receipts remain authoritative. Production hosts remain disabled while scope, budgets and retention await pilot decisions.

## Changes

The runner reuses S01's private durable state. Each attempt records its start;
partial/error outcomes leave prior complete coverage intact. Genuine findings
are persisted as output arrives, including before later timeout. Limits and
encrypted-file heuristics are coverage gaps rather than retained malware.
Private receipts preserve command policy, source revision, selected database
version/publication time, counts, exclusions, observed signatures and original
source mappings. Expiry applies only to the owning check's receipts.

Store verification is read-only content verification with `--no-trust`, without
repair. Signature updating and AV share an independent lock around database
selection and use. AV requires the full main/daily/bytecode set before launch;
receipts identify selected versions. An updater cannot change the daily channel
between the receipt and scan. Per-check locks prevent duplicate jobs; a shared
heavy-job lock prevents store verification and AV from overlapping. Conflicts
produce failed coverage rather than launching another scan.

AV uses one scanner invocation over a bounded private copy. Linux `openat2`
rejects symlink resolution and descendant mount crossings; explicit local
filesystem checks apply to scope roots. File/count/aggregate-byte/depth limits
bound preparation. Files changed while copied become coverage gaps. Numeric
staging names prevent source filenames from influencing output parsing, while
private mappings retain investigation context. Runtime staging is cleaned on
normal exit and abandoned per-job batches are removed before reuse. Bounded
stdout processing and process-group termination cover children whose leader has
already exited. The opt-in module supplies persistent jittered timers, finite CPU/memory/I/O
controls, private runtime directories and a separate bootstrap-failure reporter.
Evaluation budgets remain synthetic.

## Evidence and limits

The initial missing-helper failures were not behavioral RED; the first runner
draft was implementation-first. That deviation is preserved in
[test-contract.md](test-contract.md). Subsequent tests exposed and repaired real
coverage, traversal, process-lifetime, receipt and concurrency defects before
passing. Independent runner and module reviews passed after verified repairs. Final
integrated suite: **57 tests passed**; lint, formatting and structure checks
passed, with existing advisories. Synthetic enabled/default-disabled evaluation
returned `S01_MODULE_EVAL_OK S02_MODULE_EVAL_OK`. Final frozen Endeavour
`toplevel --dry-run --offline` passed, exit 0. Detailed commands and module
RED/GREEN evidence are in the test contract.

Pinned ClamAV 1.5.4 accepted the final command flags and private file-list over
harmless temporary files with a tiny local signature database, producing one
clean result and one expected synthetic finding. No actual host content,
production database, remote notification or live deployment was tested.

## Decisions, risks and recovery

Staging adds bounded disk I/O and does not provide an atomic snapshot of a live
filesystem. Detected mutation prevents a complete result; future pilot scope
must be quiet enough and small enough for useful coverage within its budgets.
`openat2` support is explicit for Linux x86_64/aarch64; only the local x86_64
execution path has been observed. Unsupported traversal fails conservatively.
Storage failures can prevent failure telemetry. Abrupt OOM/SIGKILL can retain
durable finding counts without final signature/source receipt details; handled
timeouts retain those details. Independent missing/stale rules remain necessary. Revert opt-in wiring to remove jobs while retaining
private evidence. No automatic finding resolution, quarantine, host activation
or deployment was added. Static/local delivery gates passed; deployment and pilot observation remain
separate, unperformed work.

## PR preparation

On 2026-11-20, the user authorized PR creation. The task branch remains based on
`96d3376b`, matching freshly fetched `origin/main`. Source is unchanged from the
reviewed 57-test pass, successful lint/format/structure checks, synthetic Nix
evaluation and Endeavour dry-run above. `just docs-check` passed during commit
preparation. This stage packages the exact S01/S02 source, tests, CI and receipts;
the coordinating agent owns subsequent publishing. No host activation is included.
