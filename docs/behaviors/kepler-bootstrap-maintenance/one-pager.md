# Preserve an operator's K3s maintenance stop

**Status:** Source repair, locally tested and independently reviewed; deployment pending.

## Outcome and why

The user asked to continue fixes after cp-1's bounded database recovery failed.
The coordinator then observed that an operator stop did not remain effective:
`k3s-bootstrap-secrets.timer` triggered at 02:03:16 UTC, and the credential
service's `Wants=k3s.service` pulled K3s back into startup. Its existing restart
policy sustained the failure loop. The coordinator stopped the timer, credential
service and K3s together at 02:12:30 UTC. This source change prevents future
credential reconciliation from undoing a deliberate maintenance stop.

The current host profile changed through concurrent work, but the cp-1 guest
closure/boot identity was unchanged; the verified trigger was the timer. This
fix does not diagnose or repair etcd and does not authorize another recovery
attempt. Activation must preserve the coordinator's current runtime baseline.

## Change and behavior

Remove the credential service's `Wants=k3s.service`. Keep `After=k3s.service`,
its normal multi-user boot activation, and the existing 30-second/15-minute timer.
Add `ExecCondition=systemctl is-active --quiet k3s.service`: inactive K3s skips
credential writes without marking the reconciliation service failed. During
normal boot K3s is independently enabled, so the retained ordering waits for its
start job; when active, the existing API readiness loop and credential updates
remain unchanged. An explicit later K3s start allows reconciliation again.

This condition is a check at service entry, not a lock. For maintenance, stop the
timer and any in-flight reconciliation before stopping K3s. Restore the timer
only after the reviewed health gate. The source changes no credentials, API
permissions, guest restart policy, timer interval, or non-cp-1 services.

## Evidence and limits

The real user-systemd fixture reads the evaluated production dependency and
condition, translates only the unit name and user-manager scope, and runs a
unique harmless guest, reconcile service and actual timer. It proves healthy
boot/repeated reconciliation, operator stop across timer ticks, skipped writes
without failure, and automatic timer reconciliation after an explicit healthy guest start (without manually starting the reconciler).
The baseline failed with `credential timer resurrected operator-stopped K3s`;
the unchanged assertion passed after the source fix. The initial Nix fixture
used the nullable `evaluatedConfig` field; that harness error was corrected to
`config.config` before the behavioral RED. It is not counted as RED.

Run `python3 tests/kepler-bootstrap-maintenance/systemd-smoke.py` locally with a
user systemd bus. All fixture units are stopped/unlinked in `finally`; no host
system units, guest VMs, secrets or cluster endpoints are used. Session receipts:
`/tmp/kepler-bootstrap-maintenance-red.log` and
`/tmp/kepler-bootstrap-maintenance-green.log`. CI runs the companion Nix
assertions, including retained boot ordering and cadence; it does not claim a
user bus or live maintenance proof.

Independent coordinator review found no blocking source issue. Its suggested
stronger timer-resume assertion was added and passed: the actual timer resumes
writes after the guest returns active. Nix assertions, lint, format, structure,
documentation links, diff-check, generated commit hooks and the offline Kepler
toplevel dry-run passed. `/tmp/kepler-bootstrap-maintenance-dry.log` records the
successful dry-run; this does not establish live activation safety.

## Delivery and recovery

The owner [recovery record](../../reference/kepler-etcd-member-recovery.md)
contains the maintenance entrypoint. Before activation, review the current
Kepler baseline and closure diff so unrelated work and healthy peers remain
intact. No live activation was performed by this author. Reverting the source
restores the unwanted start dependency, so retain the explicit timer/service
stop procedure until a healthy replacement is verified. Exact-version database
recovery remains separate and unproven.
