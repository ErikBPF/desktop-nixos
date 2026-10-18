# Scoped Hermes state backup checkpoint

**Status:** backup/rehearsal rollout prerequisite waived; failed attempts retained as history
**Stage / revision:** explicit rollout backup waiver / 9
**Checkout / base:** `feat/hermes-agent-hardening`, `880c25003d788c1c72f7cca6d9316195cfbd5178`
**Date:** 2026-10-15

## Outcome and authorized boundary

Continue authorized publication/merge/Discovery rollout without backup or rehearsal.

> what are we backing up? No need to backup these agents. Just continue

This supersedes the operational preservation prerequisite, not historical evidence.
No more backup/preflight/rehearsal/restore/deletions for this rollout. Optional
helpers/tests/contracts remain, never automatically invoked by deployment; no
Restic snapshot removed. Image rollback does not rewind mutable state.

Human seed: **“Authorize scoped backup”**: add/test two-agent encrypted backup
and isolated restore, then pre-upgrade backup using the existing sanctioned
Restic repository. **No live restore without fresh confirmation.**

Attempt 1 failed after 22.9 seconds: snapshot, phase and historical quiescence
unknown. Active 0.21.0 agents observed October 14 do not prove recovery. Metadata disproved the
credential-symlink hypothesis; no permission/path repair is justified. Its budget
closed; new evidence cannot prove historical recovery.

LAN preflight failed; overlay read-only preflight passed 2026-10-14
16:13:53–16:14:05 UTC with **zero unit actions** (`backup-overlay-preflight.json`),
resolving repository-access diagnosis, not live backup/recovery acceptance.

## Fixed scope and operating boundary

The [helper](../../scripts/hermes-state-backup.sh),
[synthetic checks](../../tests/hermes-state-backup.py) and
[behavior contract](../behaviors/hermes-state-backup.feature) cover complete homes
`/home/erik/homelab/apps/hermes-argus` and
`/home/erik/homelab/apps/hermes-agent`, including SQLite DB/WAL/SHM, sessions and
credentials, memories and skills inside encryption—not images. Existing Restic repository and sanctioned secret
source remain unchanged: no initialization, fallback store, new identity or keys.
Broad whole-home recipes and unrelated services remain outside this slice.

Retained optional supervisor covers quiescence, encrypted exact-snapshot transport,
isolated extraction/byte/SQLite checks and unsafe-archive rejection. Diagnostics
are value-free. No live restore destination exists; these helpers are not rollout gates.

## Observed validation and retained failure trail

The pre-R5 group exited zero with all three checks built on Orion: stdlib
guard/RTK, real-Restic backup and installed SDK/native-finalizer guard. Latest R5
group exited **124**, a 600-second dependency-rebuild deadline, after stdlib and
changed backup checks built on Orion and passed both real-Restic markers. Native
did not finish again; its exact unchanged derivation retains prior SDK proof.
Canonical `receipt.json` and `recovery-r5-orion-receipt.json` distinguish these runs
under `/home/erik/.local/share/opencode-v2/tmp/opencode/hermes-orion-final-4w9h0jn5/`.
No aggregate fresh GREEN or production E2E claim follows.

R5 post-GET compares exact WRITERS/TIMERS with recorded active/inactive/absent
states after all restart attempts. Failed start, failed GET or mismatch raises
sanitized recovery failure, without private state or archive-stdout pollution.
Old code observed assertion RED when a writer stayed inactive; 19 lifecycle cases,
real parser probes and real-Restic checks now pass. Fresh security/operations review
`ses_ec05e0395ffenkBAT3Z4rmE0uj` is READY. Ephemeral health oneshots are intentionally
not restarted or compared; this is not proof that all units recovered.

Private receipts retain lifecycle RED; SSH-EOF/missing-Restic repairs
(`hermes-backup-r2-w33t7o8w`); phase/preflight diagnostics
(`hermes-backup-r3-l_hzb8go`); and constructor TMPDIR RED/GREEN
(`hermes-backup-r4-dujq6idi`). Missing temporary parents and sandbox Bash were
infrastructure failures, not RED. Only copied Justfile headers were normalized to
pinned Bash; production recipes/acceptance were unchanged. Actual constructor REDs
preceded TMPDIR fixes. Encryption remained required; failures remain discovery evidence.

## Remaining gates and recovery limits

Q-BACKUP-OVERLAY-ATTEMPT-2 received the explicit answer:

> One scoped attempt

The one-attempt budget is consumed/closed. Existing overlay recipe used Discovery
`100.103.52.100`, Kepler repository `100.90.113.117`, Orion `100.72.85.73`, existing
accounts/port 2222. Attempt 2 ran 2026-10-15 13:15:48.908049–13:21:42.149267 UTC,
353.237 seconds, exit 1. Exact marker:

```text
BLOCKED hermes-state-backup {"class": "ValueError", "phase": "remote-unobserved"}
```

Canonical private receipt/log: approved temporary root,
`hermes-scoped-backup-attempt2-vz14doea/receipt.json` and `execution.log`.
No success marker/confirmed snapshot identity; snapshot may exist, cause unknown.
`post-failure-unit-state.json` records owner GET exit 0, zero unit actions:
`docker-hermes-argus.service` and `docker-hermes-agent.service` loaded/active/running;
`hermes-argus-healthcheck.timer` loaded/active/waiting;
`hermes-agent-healthcheck.timer` not-found/inactive/dead, undeployed; no start needed.
Current availability only: no before/after equality, historical recovery or fresh
image-version proof. No cleanup/retry/live restore/inference. Historical engine bound:
600 seconds **per operation**, not outage ceiling; power loss/SIGKILL/concurrency remain limits.

`rollout-backup-waiver.json` beside the attempt receipt records the superseding
decision. Live preservation remains unproved but is no longer a deployment gate.
Consumer publication/protected CI/latest build, actual deployed-baseline drift and
post-activation health/version checks remain; inference budget stays closed.
Private drafts/history remain under the approved temporary root.
