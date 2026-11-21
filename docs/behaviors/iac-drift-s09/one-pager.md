# S09: whole-service IaC drift health

## Outcome and purpose

The user-selected IaC track extends the existing Discovery drift service with
lifecycle evidence. Provider bootstrap failure, lock contention and a killed or
hung process must not look like a clean plan. A completed drift finding remains
successful coverage even if its existing notification fails. GitOps S09B owns
health alerts; this implementation adds no second finding notifier and changes
no apply authority, monitored unit or provider configuration.

## Changes and interface

The service has a finite 3,600-second startup/run deadline, including its existing
900-second shared apply-lock wait, and a 30-second stop/reporting bound. Root
`ExecStartPre` records an attempt; root `ExecStopPost` records the systemd result,
including failures before the script body. Exit 2 remains successful systemd
completion. Lock timeout is explicitly exit 75. Both drift and merged-main apply
retain the same cache-directory lock. Bootstrap reads decrypted/provider values
into checked in-memory assignments before quoted export; a failed Sops or input
read now aborts rather than disappearing inside process substitution.

Root-owned private state and one bounded last-result receipt live under
`/var/lib/homelab-iac-drift-health`. A separate root-owned metrics directory feeds
Alloy. The legacy writable stream drops the reserved `homelab_iac_drift_*`
namespace; the trusted collector fixes the host label and removes extra labels.
The producer account remains trusted to supply its structured result: root
publication does not authenticate arbitrary writes by that same account.

Gauges use only `instance`. Suffixes are `last_attempt_seconds`,
`last_complete_seconds`, `last_publish_seconds`, `duration_seconds`, `outcome`,
`notification`, and `lock_contention`. Outcome values are 0 never, 1 running,
2 clean, 3 drift, 4 error, 5 timeout, 6 lock contention. Notification values are
0 not required, 1 HTTP delivery succeeded, 2 failed, 3 not configured, 4 unknown.
Only identity-validated clean/drift results advance completion; delivery failure
remains independent. Receipts record revision/scope digests, never plan output
or credentials. Missing/invalid results fail closed.

## Evidence and review

The original eleven contracts passed before the new lifecycle assertion failed
because the reporter was absent. Transition tests cover bootstrap, lock, timeout,
process death, clean, drift, delivery failure and recovery. A real pinned Alloy
fixture validates the full generated configuration, preserves a backup metric,
rejects forged legacy drift metrics and fixes trusted identity. Discovery module
evaluation and targeted offline toplevel dry-run passed; lint, format and structure
checks passed. The owner `just dry discovery` attempt stalled on an Orion cache
fetch and was canceled; the documented raw offline equivalent passed instead.

Independent review found that a producer-owned result could grow after `fstat`.
The regression first failed with clean outcome 2 instead of error 4. Reading at
most 4,097 bytes and rejecting overflow fixed it while preserving regular-file
and no-symlink checks. Reviewer reran all 18 focused tests successfully. Session
logs preserve RED/GREEN and the Discovery dry-run; no live plan, apply, credential
change, deployment or notification ran.

After pinning the merged S08 producer and rebasing onto core PR #488, all 18
focused tests passed again with pinned Alloy 1.21.3. Lint, format, structure,
documentation links and diff checks passed. The final offline Discovery toplevel
dry-run exited 0; `/tmp/s09-discovery-final-dry.log` records the candidate
without building or activating it.

## Dependency and recovery

S08 merged through IaC PR #176 after exact-head CI and Hackerman review passed.
Desktop pins immutable revision `7c5d785420c794769cb2c4952fb9916e99788450`;
the matching pin assertion and lockfile are updated together. S08 clears stale
results before planning, and this consumer clears before bootstrap and rejects
failed invocation or incompatible result identity. Runtime budget calibration,
S09B consumer deployment and actual Discovery evidence remain coordinator work.
Rollback restores the previous specific pin and reporting wiring while retaining
apply serialization, credentials, the existing notifier and private evidence.
