# Endeavour integrity pilot operations

**Status:** Prepared source; live activation and seven-day observation are separate gates.

The coordinator owns publication, backend enrollment, staffed commands and real
notification evidence. Only `/home/erik/Downloads` is approved for mutable-file
AV. No other home path, quarantine, real-finding clear, host outage or global
silence is authorized. The coordinating Homelab record is
`docs/plans/host-integrity/pilot-runbook.md`.

## Three explicit stages

The committed default imports the Endeavour integrity aspect with three checks,
no jobs and no timers. Deploy this collector-only revision with existing owner
recipes `just dry endeavour` then `just switch endeavour`, after reviewing the
running/candidate closure diff. Never run `just upgrade` for this pilot.

After identity and never-run gauges reach the backend and the three expected
checks are enrolled, a separately reviewed source revision sets
`services.hostIntegrity.pilot.enableJobs = true`. The declared jobs then exist
but their timers have no `wantedBy`; scheduled catch-up cannot race drills.
Use `just integrity-store-preflight`, then `just integrity-start signatures`,
`just integrity-start store` and `just integrity-start av` sequentially. The store
preflight performs a read-only daemon query in the actual verification sandbox.
A successful systemd exit is not a clean scan: `just integrity-status` shows
producer states and service resource counters.

Only after controlled drills may a third source revision set
`services.hostIntegrity.pilot.enableSchedules = true`. Schedules are daily
03:10 for definitions, daily 03:40 for store contents, Sunday 04:40 for AV, with
15-minute randomized delay and persistent catch-up. Record the actual UTC
observation start and seven-day end; no local test advances that clock.

## Bounds and existing conditions

All jobs use 25% CPU, nice 19 and I/O weight 10. Deadlines are 900 seconds for
definitions/AV and 1800 for store verification; memory ceilings are respectively
768 MiB, 2 GiB and 512 MiB. AV caps are 64 MiB per file, 128 MiB expanded scan,
256 MiB staged total, 2000 entries, depth 8 and 256 KiB output. Private receipts
retain 30 days, at most 128 per check. These are provisional limits, not measured
performance promises.

Metadata-only preflight found known oversized/symlink exclusions. Partial
Downloads coverage is expected and stays visible. The pre-existing
`restic-backups-endeavour-home.service` failure is not reset or repaired by this
pilot. `_integrity-window` rejects active backup/jobs, active integrity timers,
less than 4 GiB available RAM or less than 1 GiB free `/run`, and displays swap
and available memory before each controlled operation.

When jobs are enabled, each actual Restic invocation takes the same root-private
lock as integrity jobs and canaries. Integrity refuses a busy lock; Restic waits
at most 1860 seconds and returns status 75 on lock timeout. Backup services may
remain active while preparing/waiting, and a scan can enter between Restic
invocations, but protected data operations do not overlap. Existing backup
arguments, secrets, preparation and cleanup remain owned by the Restic module.

Store verification explicitly uses `--store daemon --no-trust`. Pinned Nix
2.35.6 commit `4c9c2490ff10c6fc30f9675273af989569cf37da` performs content hashing
in the client (`src/nix/verify.cc`, UDSRemoteStore's local filesystem/NAR
accessors); only metadata uses the daemon. The scanner cgroup bounds the heavy
work. Do not open live SQLite through `local?read-only=true`.

## Synthetic finding and reviewed resolution

Use `just integrity-canary partial`, `just integrity-canary error`, then
`just integrity-canary finding`, respecting the coordinator's firing/recovery
gates between cases. The template inherits the real AV sandbox and invokes the
pinned scanner against temporary harmless data and a tiny custom signature.
It never reads Downloads or updates production definitions. Synthetic scope
always remains partial/failed and never advances real Downloads completion.

After the finding notification is actually received, run the normal Downloads
job again and inspect private receipts. A zero-new-findings result can be partial;
resolution does not hide those skipped items. Create an operator-reviewed JSON
file in the root-private state directory, mode `0600`, containing exactly
`reviewer`, `reason`, `incidentReceipt`, `recoveryReceipt`. Receipt values are
basenames of the specific synthetic incident and latest normal zero-finding,
zero-error recovery attempt. Do not print private source paths in coordination
receipts. Use the exact digest from `just integrity-status`:

```bash
just integrity-resolve EXPECTED_STATE_SHA256 /var/lib/host-integrity/review.json
```

The helper requires root, takes run/state locks, rejects changed state, running
jobs, mismatched evidence or any genuine-finding marker, and writes a private
authorization audit before clearing only the synthetic count. State, skips,
errors, attempt and completion times remain intact. Genuine provenance is stored
before positive counter publication and survives missing receipts or a crash;
there is no genuine-marker removal or real-finding resolution command here.

## Scoped missing-check drill and restoration

No host outage is involved. Before starting, the coordinator confirms production
missing-check `for` plus staleness/lookback fits the staffed 15-minute scenario;
otherwise declare a longer bounded window before beginning, or defer the drill.
Do not call a shortened fixture proof of elapsed production time.

With manual jobs staged and integrity timers stopped, arm restoration before
omitting the single AV metric file. These are local Endeavour commands:

```bash
just _integrity-window
test "$(systemctl show host-integrity-report.service -p ActiveState --value)" = inactive
restore_unit="host-integrity-missing-restore-$(date -u +%Y%m%dT%H%M%SZ)"
sudo install -d -m 0700 /var/lib/host-integrity/pilot-hold
held="/var/lib/host-integrity/pilot-hold/av-${restore_unit}.prom"
sudo test ! -e "$held"
sudo systemd-run --unit="$restore_unit" --on-active=12m --timer-property=AccuracySec=1s --collect /run/current-system/sw/bin/systemctl start host-integrity-report.service
sudo systemctl is-active --quiet "$restore_unit.timer"
systemctl show "$restore_unit.timer" -p ActiveState -p NextElapseUSecMonotonic
sudo test -s /var/lib/host-integrity-metrics/av.prom
sudo mv --no-clobber /var/lib/host-integrity-metrics/av.prom "$held"
```

During omission no producer, reboot or unrelated operator action may race the
staffed window. Record actual backend missing-check firing, then restore from
durable state rather than copying an old metric over a newer publication:

```bash
sudo systemctl start host-integrity-report.service
sudo test -s /var/lib/host-integrity-metrics/av.prom
just integrity-status
```

Verify backend recovery and normal backup telemetry **before** cancelling an
unelapsed restoration timer with `sudo systemctl stop "$restore_unit.timer"`.
If automatic restoration already fired, record it instead. The native timer is
a safety action, not a guarantee against host/storage failure. Preserve the held
metric as private drill evidence. Stop subsequent drills after failed recovery
or three repairs of one failure.

## Exact known-good rollback

Before activation verify generation 211 still resolves to the recorded baseline
and its activation program remains executable. The owner recipe guards target,
generation and closure equality, restores the exact profile generation, then
activates that same closure and verifies both pointers. First stop pilot timers
and all running pilot jobs, including canary instances; preserve state and receipts:

```bash
sudo systemctl stop host-integrity-signatures.timer host-integrity-store.timer host-integrity-av.timer
sudo systemctl stop host-integrity-signatures.service host-integrity-store.service host-integrity-av.service 'host-integrity-av-canary@*.service' host-integrity-store-preflight.service
just integrity-rollback 211 /nix/store/9qza0zd7kkv2958xg2lmgyhyxahg9rq8-nixos-system-endeavour-26.11.20261115.5c3cda7
```

Do not use a blind previous-generation rollback or rebuild the pilot checkout
as recovery. Restore backend expectations/routing coherently through their
owner, retain private state/receipts, and verify ordinary telemetry afterward.
