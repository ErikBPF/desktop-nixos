# S02: bounded integrity jobs

## Human seed

> invoke agent to do slices 0 to 3

## Accepted scope

Implement Homelab's `docs/plans/host-integrity/slices/S02-scans.md` and frozen
`docs/plans/host-integrity/interface.md` revision 1. S01's persistent reporter is
the shared state boundary. Signature updating, store content verification and
scoped AV are separate jobs with explicit budgets, jittered persistent timers,
restricted receipts and no overlapping heavy jobs. Actual database publication
age is independent of successful updater execution.

No production host is enabled. Paths, CPU/memory/I/O limits, deadlines, aggregate
copy limits, output limits and retention in evaluation fixtures are synthetic;
they do not settle pilot decisions. Store verification uses
`nix --offline store verify --all --no-trust`, without repair. No quarantine,
automatic finding clear, network mount traversal, or shared-daemon replacement.

Coverage exclusions and ClamAV Limits/Encrypted heuristics are partial coverage,
not malware findings. Genuine findings remain visible if later work fails.
Private source mapping makes staged-file findings investigable without leaking
paths into metrics. A transient copy is not a filesystem snapshot: concurrent
changes detected while copying invalidate that file's coverage. Pilot scope must
still be reviewed for useful coverage and feasible copy cost.

Handled tool failures exit normally after publishing failed metrics and a receipt.
Systemd unit success therefore does not imply a clean scan. Separate OnFailure
publication covers bootstrap, unit-level and uncaught failures without creating
a duplicate attempt for each already recorded tool failure.
