# Targeted cp-1 recovery activation

**Status:** Guest recovery remains blocked after the approved preview failed on
2026-11-22, before dry activation. The [observed host receipt](cp1-boot-containment-check.md) records the reviewed
containment deployment and verification; this closes the earlier old-installer
hold for that observed baseline.
The helper incorrectly required a service-only `MainPID` property on an inactive
timer. The source repair below requires review before another preview. No member
removal, quarantine, guest switch or K3s start followed this failure. Follow the
[ordered recovery sequence](cp1-durable-recovery.md); old manifests and former
post-health runner-persistence instructions remain superseded.

## Purpose and boundaries

The recovery candidate preserves the guest kernel, initrd, interfaces, volumes and
shares while joining cp-3 without `cluster-init`. K3s keeps the stock unit
defaults: `Restart=always`, no startup timeout and the `multi-user.target`
boot edge, so the node rejoins on its own after a host reboot. Bootstrap service/timer are disabled in source; the
manifest reconciler loses its K3s start dependency and gains an active-service
condition. These are the only allowed unit changes.

The helper runs only on Kepler and addresses only cp-1. It never switches Kepler,
restarts a VM, removes an etcd member, moves WAL/backend files, or restores an old
configuration. Any replacement procedure, after durable boot containment is verified, must remove the failed member
and preserve/quarantine its state **before** activation, because activation starts
K3s. A new cp-1 member ID is expected; survivor IDs and cluster identity must remain.

## Prepare exact artifacts and observations

After candidate publication, `just cp1-stage-artifacts REVISION` builds exactly the
cp-1 toplevel, runner, Nix executable, Python executable and closure registration
from that full commit.
It copies through authenticated, strictly verified SSH with normal Nix signature
checks, then creates root-owned task GC links under
`/nix/var/nix/gcroots/cp1-recovery-REVISION`. Neither Kepler system profile changes.
GC roots remain until reviewed cleanup; copying alone is not persistent GC safety.

`just cp1-artifact-metadata REVISION` exports evaluated paths and hardware. Run it
for the reviewed baseline and candidate. The actual nested attribute is
`nixosConfigurations.kepler.config.microvm.vms.cp-1.config.config`.

The existing helper manifest shape is retained below as reference, not an
executable recovery input. It does not validate the effective host installer:

```json
{
  "sourceRevision": "FULL_CANDIDATE_COMMIT",
  "knownHosts": "/absolute/preverified/cp1-known-hosts",
  "knownHostsSha256": "SHA256_OF_THAT_FILE",
  "baseline": {
    "hardware": {},
    "hostCurrent": "OBSERVED_KEPLER_RUNNING_CLOSURE",
    "hostProfile": "OBSERVED_KEPLER_PERSISTENT_CLOSURE",
    "guestCurrent": "OBSERVED_CP1_RUNNING_CLOSURE",
    "guestProfile": "OBSERVED_CP1_SYSTEM_PROFILE",
    "guestBootId": "OBSERVED_CP1_BOOT_UUID",
    "runner": "OBSERVED_CP1_CURRENT_RUNNER",
    "bootstrapTimerState": "OBSERVED_IS_ENABLED_STATE",
    "bootstrapServiceState": "OBSERVED_IS_ENABLED_STATE"
  },
  "candidate": {}
}
```

Replace `baseline.hardware` and `candidate` from the two source exports; replace
all observation placeholders with fresh read-only evidence. Require baseline
exported toplevel/runner to match the running guest and recorded runner. Do not
invent paths or infer SSH trust from a live disk read that reports errors. Record
existing bootstrap mask states so a later release cannot silently unmask a unit
that was already intentionally masked.

## Existing helper behavior — held, not execution instructions

Before preview, require `k3s-bootstrap-secrets.timer` explicitly inactive.
Require `k3s.service`, `k3s-bootstrap-secrets.service` and
`k3s-manifest-reconcile.service` inactive/failed with MainPID zero. Timers do not
have a MainPID property; missing service properties or failed property reads
reject the guard. Their maintenance stop
belongs to the approved recovery procedure. Confirm surviving etcd quorum/health,
matching fixed-revision hashes and the preserved failed-state archives.

The held helper preview invokes NixOS dry activation. Do not invoke it while
the boot-containment gate remains open.
This upstream dry activation does not switch services, but its user-management
script may normalize `/root` and `/home` directory metadata; it is not promised
to make zero filesystem writes. Include that bounded behavior in live approval.
The existing activation implementation loads guest registration, selects
the new guest profile and switches only that guest. The candidate has no K3s
boot target edge. After the approved member removal and datastore quarantine,
the helper switches configuration (120 seconds), then explicitly starts K3s
once (330 seconds, enclosing its 300-second service timeout). The SSH operation
has a 660-second outer budget covering preview (60 seconds), switch, start and
cleanup. Signal/failure handling attempts a bounded stop and checks K3s PID zero;
transport loss can prevent confirmation and must be treated as uncontained until
verified. No automatic old-etcd restart or bootstrap unmask occurs.

The helper asserts unchanged Kepler running/persistent profiles, cp-1 current
runner and guest boot ID. It intentionally leaves the host runner unchanged.
That invariant does not prove safe reboot selection: a later installer run can
replace `current` independently of the guest switch.

## Required source-owned containment before removal

The former executable post-health `current`-symlink persistence block is
withdrawn. Delaying persistence until health leaves a failed-switch/reboot window;
changing only the symlink does not survive the old declarative installer.

The [owner containment receipt](cp1-boot-containment-check.md) records successful
durable host selection at 14:11 UTC. Before any member removal or quarantine,
require that observed baseline to remain unchanged; re-establish the gate on drift. Evidence must bind the published source and persistent host closure to
the installed `install-microvm-cp-1` definition and its declared runner, prove
that the selected runner contains the reviewed guest configuration, and cover
failure and reboot ordering. Preserve concurrent host changes, sibling guests,
archives and the distinct `booted` runner identity. Do not treat manual remote
unit edits, an unverified symlink, or old WAL restart as a substitute.

Refresh the private manifest only after the new host and runner baselines are
observed. Its `baseline.runner` may then equal the candidate runner while the
running guest still uses the old closure; record those facts separately. The
current helper does not itself establish or verify the durable installer gate.
A source fix being merged, artifacts being copied, or this hold being documented
does not authorize host deployment or guest activation. The final revised
procedure needs independent review and fresh scope-appropriate live approval.

## Evidence and limits

Command-level fixtures cover preview, identity/PID/drift rejection, signal and
failed-switch containment, finite budgets, strict manifest values and exact unit
changes. The unit comparator also passed against actual built baseline `5dd7…`
and candidate `xp0g…`; source-disabled bootstrap units resolve to `/dev/null`.
REDs are in `/tmp/cp1-{commands,pid-budget,active-service,unit-delta,condition-path}-red.log`.
These are preparation checks, not live activation or persistent recovery proof.

### Staging output correction

The first owner staging attempt stopped before copying: Nix selected the Nix
package's manual output as well as its executable output, producing five paths
instead of the required four. Selecting `c.nix.package.out` explicitly produced
the four reviewed artifacts. The failed output-count guard caused no remote
mutation; the actual cached build confirmed the corrected output set.

The post-staging read-only check exposed an incorrect default runner directory
in the first helper draft. Kepler's owning source explicitly sets
`microvm.stateDir = "/fast/microvms"`; the current and booted links there both
resolve to the retained `324az74...` runner. The guard and persistence procedure
now use that exact directory, and immutable metadata exports and validates it.
The corrected host-path fixture failed before the repair. No guest operation
ran against the incorrect path; the helper would have stopped at preflight.

Root's read-only guest preflight also confirmed the normal microVM boot has no
`/nix/var/nix/profiles/system` entry. Record `guestProfile: "absent"` only when
both the file and symlink are absent. The guard rejects unexpected appearance
or dangling links; activation creates the first guest profile. Existing profiles
still require the exact observed store path. This exception never applies to
the host profile. Disposable actual-file tests cover all six combinations.

### Authorized artifact staging receipt

At 2026-11-22 02:46 UTC, the owner staging recipe completed for candidate
`7daee157e729dec33b250e2dfff39998bfea185b`. The four reviewed artifacts are retained
under `/nix/var/nix/gcroots/cp1-recovery-7daee157e729dec33b250e2dfff39998bfea185b`
(root:root, mode 0700). Normal Nix signature verification remained enabled.
Kepler's boot ID, running `zi7mrr...` closure and persistent `mhd9qc...` wrapper
were unchanged. Current and booted cp-1 runners still resolve to `324az74...`.
The exported candidate metadata, now including the source-owned state directory,
has SHA-256 `dae5fa3806e2f2ed9b41776787e2818c78b2035a798877ed1e283d6ff367a0e7`.
No guest preview, membership operation, activation or runner persistence was
performed. These remain within the concrete approval gate above.

### Declared comparator runtime

Kepler's interactive PATH has no Python. The first shell draft therefore would
have stopped before guest SSH. The helper now stages the candidate package set's
Python executable output as a fifth GC-rooted artifact, exports its exact path,
and invokes that path for unit comparison. An empty-PATH command regression
failed with `python3: command not found` before the fix. No global host package
installation is required; the guest closure is unchanged. Earlier four-artifact
receipts remain historical evidence, not the complete final runtime contract.

The first hosted lint run also caught the owner's command-layout contract:
`--max-jobs 0` must occur on the `--builders` line or immediately after it.
Moving the already-present flag onto that line preserves build behavior and
passes the unchanged contract. The combined helper and owner recipe suite now
passes 78 tests; the helper alone passes 39. The comparator uses Python isolated
mode (`-I`) to ignore inherited user-site and Python environment overrides.

### Boot-start guard revision

Hosted review identified that the temporary candidate still had a boot target
edge. The revised source removes it; the helper rejects a remaining `WantedBy`
directive or target/alias link and permits only the reviewed old edge's removal.
It explicitly starts K3s once after configuration switch; failed start triggers
the existing bounded stop, never a retry. Actual composed-command regressions
failed before this change. Earlier staged `7daee157` and `a351b9a` candidates and
private manifests are superseded and must not be executed; retain their roots
and receipts until reviewed cleanup. The revised built-unit comparison and
final artifact staging remain pending the source owner's build.

Hosted review also reproduced post-operation host drift being masked by Bash's
`errexit` behavior inside an OR-list function call. Every host comparison now
returns failure explicitly. The actual function is exercised in both bare
preflight and OR-list postcheck contexts; changed running or persistent host
profiles fail even when the runner still matches. Both postcheck regressions
failed before repair; no live activation had occurred.

The helper masks K3s for the switch so the boot edge cannot start it inside the
120-second transaction, then verifies the selected guest closure and boot
identity, loaded `Restart=always`, bootstrap masks, and the loaded K3s command
joining cp-3 without `--cluster-init`, and only then unmasks and starts K3s under
its own 330-second budget. A successful switch exit alone is not enough.
Stale-closure and stale-command fixtures both fail before that start. Loaded
command values are not printed. The final active, boot and closure checks still
run after the one start.

### Documentation hold correction — 2026-11-22

Final failure-path review superseded the executable post-health persistence
instructions. This docs-only correction removes that shell block, marks preview
and activation held, and requires source-owned installer/runner containment
before removal. Earlier RED/GREEN, source reviews and staging receipts remain
historical evidence; none proved that the old host installer had been replaced.
Helper code and live host/guest state are unchanged by this correction. Focused
document-link and diff checks validate the edit, not runtime recovery.


### Timer-property guard repair — 2026-11-22

The first approved guest preview returned exit 1 before NixOS dry activation.
Read-only diagnosis found the host-side helper preflight passed, while the
inactive bootstrap timer returned no MainPID property. The fixture had invented
MainPID=0 for every unit and therefore missed this systemd distinction.

The fixture now returns empty successful MainPID output for timers. Against
unmodified production code, the preview-success assertion failed before any
switch/profile call (nine failures, sixteen passes across the command suite).
The guard now checks the timer's ActiveState separately, accepting only inactive;
services retain inactive/failed plus PID-zero requirements. Property commands are
standalone assignments so nonzero exits cannot be hidden by matching output.
Empty, unknown, failed or active timer states and missing/error service PID reads
fail closed. No timeout, activation, identity, membership or rollback bound changes.

The targeted suite passed 57 tests after repair. RED/GREEN logs are local
`/tmp/cp1-timer-guard-red.log` and `/tmp/cp1-timer-guard-green.log`; the initial
`python3 -m pytest` invocation lacked pytest and is infrastructure failure, not
RED. These disposable command fixtures execute the actual guest shell but do
not prove live recovery. No live action was performed while implementing this
repair. Source review and a successful owner preview remain required before
continuing the ordered procedure.
