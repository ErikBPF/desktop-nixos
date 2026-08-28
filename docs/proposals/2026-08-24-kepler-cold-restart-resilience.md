# Kepler cold-restart resilience

**Status:** Implementation planned — `/pl`, `/ip`, and `/rv` complete. The
behavior contract remains unautomated; implementation and a maintenance-window
proof remain.

## Destination

After an abrupt restart, Kepler returns without redirecting pool-backed bind
writes to the OS disk, remains remotely diagnosable when storage is degraded,
and gives the operator one bounded, repeatable verdict for host, storage,
Compose, and k3s recovery.

This proposal refines the Kepler reboot-return gate in the homelab
[`stateful-stack and release hardening`](https://github.com/ErikBPF/homelab/blob/main/docs/proposals/2026-07-13-stateful-stack-release-hardening.md)
program. The behavior contract is
[`kepler-cold-restart.feature`](../behaviors/kepler-cold-restart/kepler-cold-restart.feature).

## Grounded current state

- `/fast` and `/bulk` are ZFS datasets mounted with `nofail`; boot deliberately
  continues when either pool is unavailable.
- The five k3s MicroVM units already require `/fast/microvms` before startup.
- Kepler's rootless Compose units start from the lingering user manager after
  `servarr-pull`, but do not verify their required ZFS mounts.
- `servarr-pull` contacts GitHub on ordinary boots. Its failure does not require
  the Compose units, but the resulting local-checkout behavior is not part of
  the reboot-return verdict.
- `infra`, `buzz`, and `sync` use both pools; `security`, `whisper-gpu`, and
  `qwen4b-gpu` use `/fast`; `monitoring` uses neither.
- A plain directory at `/fast` or `/bulk` is currently sufficient for Compose
  bind creation. If a pool is missing, that can redirect writes to the Btrfs OS
  disk.
- `reboot-kepler` proves only a down/up SSH transition. It does not prove pool
  identity, declared user units, containers, MicroVMs, or cluster health.
- Boot counting gives a new system generation three attempts and avoids the
  aggressive watchdog behavior that previously caused reboot loops.
- Daily local and offsite backup-success gauges are fresh. Both weekly Buzz
  restore-drill gauges are stale beyond their existing nine-day contract.
- Some state remains in rootless Podman named volumes on the OS disk. Surviving
  a reboot is not the same as surviving loss of that disk.

## Actors and outcomes

| Actor | Required outcome |
|---|---|
| Operator | SSH or Tailscale access and one exact recovery verdict after restart. |
| Stateful workload | Starts only against its declared, mounted ZFS datasets. |
| Monitoring | Remains available when its own dependencies are present and reports degraded storage/startup. |
| Upgrade automation | A bad OS boot can roll back without treating a missing data pool as a bad generation. |
| Recovery operator | Can prove non-rebuildable state is restorable, not merely present after reboot. |

## Decisions

### D1 — Cold restart is a forced power cycle

The operator forces power off without an orderly userspace or Compose shutdown,
waits two minutes with Kepler powered off, then powers it on. The return deadline
begins at power-on. Software cannot promise zero in-flight data loss or protect
hardware from unsafe power.

### D2 — Keep the administration plane independent of data pools

`nofail` remains. Missing `/fast` or `/bulk` must not block the OS, SSH,
Tailscale, or storage diagnostics. A degraded but reachable host is safer than
an unavailable host waiting forever for storage.

### D3 — Fail stateful writers closed on exact storage identity

Each declared Compose stack has an explicit storage requirement:

| Stack | Required storage |
|---|---|
| `infra` | `/fast`, `/bulk` |
| `buzz` | `/fast`, `/bulk` |
| `monitoring` | none |
| `sync` | `/fast`, `/bulk` |
| `security` | `/fast` |
| `whisper-gpu` | `/fast` |
| `qwen4b-gpu` | `/fast` |

The gate verifies the expected ZFS dataset, filesystem type, and mountpoint.
Directory existence alone never passes. An affected stack performs no Compose
start and creates no bind data below the missing mountpoint.

The existing MicroVM `/fast/microvms` dependency remains authoritative for the
k3s guests.

### D4 — Recover late storage explicitly and idempotently

If a pool becomes available after boot, affected stacks stay stopped until the
operator runs one documented recovery path. That path revalidates exact pool
identity, resets only the affected failed/start-limited units, starts them in
declared order, and can be repeated without duplicate owners or container
recreation once healthy.

Automatic late-pool recovery is deferred. Surprise writes after a degraded boot
are a larger risk than requiring one explicit command.

### D5 — A remote source outage must not erase known local desired state

When the Servarr remote is unavailable, Kepler may start from its existing
clean, previously activated checkout after validating its machine path and
render. The outage is reported as source-sync degradation. It must not rewrite
the checkout, silently select another branch, or make GitHub a cold-boot
availability dependency.

"Previously activated" means the checkout still matches the existing
machine-bound v2 pin and exact commit/tree checks plus a new read-only check that
the tracked worktree and index are clean. Sanctioned untracked runtime files do
not make the checkout dirty. An absent, malformed, wrong-machine, dirty, or
mismatched state fails the affected workload path closed; it never falls back
to a remote branch.

### D6 — One verifier owns componentized reboot-return verdicts

Extend the documented reboot path rather than adding another lifecycle
mechanism. Within a 10-minute settle window after power-on it verifies:

1. SSH return and zero unexpected failed system units;
2. Tailscale and the user manager;
3. exact `/fast` and `/bulk` mounts, ONLINE pools, scrub/error state, and free
   space;
4. source-sync status, every declared Compose unit, and intended containers,
   with explicit degraded results for offline source or storage-gated stacks;
5. all declared MicroVMs plus separate k3s control-plane, platform-reconciler,
   and workload-reconciliation status;
6. freshness of backup and restore evidence as a separate recovery-readiness
   result.

The value-free result separates `operational-return`, `source-sync`, and
`recovery-readiness`. Stale restore evidence cannot hide a successful host
return, and a successful host return cannot hide stale recovery evidence. Each
failed gate names the exact recovery entrypoint. Re-running the verifier is
read-only and gives the same verdict for unchanged state.

### D7 — Do not bind data-pool health to boot blessing

Boot counting continues to judge whether the OS reaches its normal boot target.
A missing HBA or data pool must not demote an otherwise valid generation.
Post-boot storage/workload verification is a separate degraded-state signal.
No runtime watchdog or panic-on-transient-failure behavior is added.

### D8 — Recovery proof covers every non-rebuildable state owner

Before the overall resilience claim closes, every Kepler named volume and bind
mount is classified as rebuildable, accepted-loss, or restore-tested. Existing
weekly local and offsite Buzz restore drills must produce fresh evidence within
the current nine-day alert threshold. This extends the active P7 state ledger;
it does not require moving every named volume to ZFS.

### D9 — Keep repository ownership intact

- `desktop-nixos`: mount gates, boot ordering, reboot/recovery verifier, host
  diagnostics, and k3s substrate.
- `servarr`: Compose paths, volume classification, backup/restore jobs, and the
  incorrect `/mnt/fast` and `/mnt/bulk` examples.
- `homelab`: cross-repository status and rollout gate only.

No consumer reads another working tree during build or deployment.

## Dependency map

```text
exact ZFS identity
  -> per-stack startup gate
  -> degraded-boot behavior
  -> explicit recovery path
  -> reboot-return verifier

validated local Servarr checkout
  -> remote-independent known desired state
  -> source-sync verdict

state inventory
  -> backup/accepted-loss classification
  -> fresh local + offsite restore proof
  -> resilience claim
```

## Risks and review gates

| Risk | Gate |
|---|---|
| A missing pool redirects bind writes to `/` | Exact dataset/type/mountpoint check before Compose. |
| A global storage gate hides useful diagnostics | Requirements remain explicit per stack. |
| A transient hardware fault rolls back a good OS generation | Storage health stays outside boot blessing. |
| GitHub or DNS is unavailable during boot | Validate and use the existing clean checkout; report source-sync degradation. |
| Recovery creates duplicate runtime owners | Repeated recovery must be a no-op once healthy. |
| A reboot looks green while data is unrecoverable | State ledger plus current restore evidence. |
| A verifier leaks runtime secrets | Value-free output; no environment or secret content. |

Security, reliability, architecture, compatibility, tests, and operations all
apply. Performance and accessibility do not materially change in this slice.

## Out of scope

- Automatic power-loss prevention, UPS purchase, or NUT configuration until
  the attached power hardware is inventoried.
- Runtime pool disappearance after workloads have started.
- Narrowing Kepler NFS `no_root_squash`; that remains the separate H2 security
  gate.
- Rolling k3s guest restart, active/active workloads, or a second storage host.
- Replacing rootless Podman, ZFS, systemd boot counting, or the existing
  `servarr-pull` lifecycle.
- Recurring automated hard-power tests. Offline missing-pool fixtures and the
  documented reboot path are implementation gates; one staffed, explicitly
  authorized cold-start witness is the final operational gate.

## Implementation plan

The smallest design reuses the existing rootless Compose orchestration,
`servarr-exact-revision`, Kepler recovery tooling, systemd mount conditions,
and `just reboot-kepler`. It adds no daemon, watcher, cross-working-tree build
input, or automatic pool import.

### Dependencies and order

```text
Servarr storage/state contract published at one exact commit
  -> desktop-nixos gates and fixture checks
  -> exact Servarr commit pinned on Kepler
  -> reviewed Nix generation activated
  -> staffed cold-start proof
```

Land producer changes before consumer changes. Deployment consumes only the
published, machine-bound Servarr commit. The ordinary staffed activation may
close the separate repository-responsibility activation gate; it does not close
this proposal until the later forced-off proof passes.

### Slice 1 — Publish the Kepler workload contract

**Owner:** `servarr`

**RED:** Add one fixture check under `machines/kepler/tests/` that fails until a
versioned, value-free Kepler contract:

- names all seven declared stacks and their exact `/fast`/`/bulk` requirements;
- rejects a missing stack, unknown mount, or requirement inconsistent with the
  Compose bind sources;
- classifies each non-rebuildable bind and named volume as rebuildable,
  accepted-loss, or restore-tested; and
- retains the existing nine-day local/offsite Buzz restore-evidence contract.

**GREEN:** Add the minimum contract beside the Kepler Compose files and extend
the existing P7 state records only where an owner lacks classification. Reuse
the existing Buzz restore scripts and metrics; do not create another backup
ledger or scheduler.

**Verify:** Run the focused Kepler tests, then the repository's existing
Compose/config validation. Publish the passing commit before any consumer
change.

### Slice 2 — Gate each writer on exact storage identity

**Owner:** `desktop-nixos`

**RED:** Add fixture-driven checks under `tests/kepler-cold-restart/` for every
scenario-outline row plus the lookalike-directory case. Prove that monitoring
still starts without either pool and that one missing pool cannot block SSH,
Tailscale, or storage diagnostics.

**GREEN:** Extend the existing Kepler recovery/tooling module and Compose-unit
wiring with one value-free storage check. Before Compose runs, validate the
declared ZFS dataset, filesystem type, and mountpoint. Keep the existing
MicroVM mount dependency, strengthening it only if the fixture proves directory
lookalikes can pass. Do not add a global storage target: each stack evaluates
only its own published requirements.

**Verify:** Run the focused fixtures, `just dry kepler`, `just lint`, and
`just fmt-check`. A missing-pool fixture must show no Compose invocation or bind
creation.

### Slice 3 — Make exact desired state boot-safe offline

**Owner:** `desktop-nixos`

**RED:** Extend `tests/servarr-exact-revision/` and the orchestration wiring
checks. Cover an unavailable remote with a valid clean v2 pin, plus absent,
malformed, wrong-machine, dirty, commit-mismatched, and tree-mismatched states.
The valid case must not contact the network or select a branch; every invalid
case must block dependent stacks with a value-free reason.

**GREEN:** Reuse the exact-pin validation path before `servarr-pull` supplies
Compose state. Move v2 checkout mutation into the existing explicit
`just pin-servarr` transaction, reusing the helper's current rollback pattern;
the exact-pinned boot path becomes read-only validation. Record source-sync as
healthy or degraded without making remote reachability an operational-return
dependency. Do not introduce a second repository lifecycle or silently repair
a dirty checkout.

**Verify:** Run the exact-revision and orchestration test directories, then
`just dry kepler`. Re-run existing Discovery, Orion, and fleet-pin checks
because they share the exact-revision helper.

### Slice 4 — Add one verifier and one explicit recovery path

**Owner:** `desktop-nixos`, consuming the published Servarr contract

**RED:** Bind the remaining behavior scenarios to fixture-driven checks for:

- componentized `operational-return`, `source-sync`, and
  `recovery-readiness` verdicts;
- exact failed-gate and recovery-entrypoint reporting without values;
- all five MicroVMs, k3s control plane, platform reconcilers, and workload
  reconciliation as distinct gates;
- stale restore evidence degrading only recovery readiness; and
- read-only repeat verification plus idempotent affected-stack recovery.

**GREEN:** Add `verify` and `recover-storage` modes to one Kepler recovery tool.
The verifier reads state only. Recovery revalidates mounts, resets only failed
or start-limited affected units, and starts them in declared order. Extend
`just reboot-kepler` to call the verifier after SSH returns; expose the same
verifier separately for cold-start and diagnostic use.

**Verify:** Run the focused fixtures twice against unchanged state, the Kepler
dry build, and the repository lint/format gates. Exercise missing-pool and
offline-source fixtures before touching Kepler.

### Slice 5 — Roll out and witness the contract

**Owners:** `servarr` -> `desktop-nixos` -> operator -> `homelab`

1. Pin the published Servarr commit on Kepler and record exact pin/checkout
   verification without values.
2. Stage and activate the reviewed Kepler generation with a staffed local
   console; run the verifier and keep the prior generation and prior Servarr
   pin as rollback inputs.
3. Refresh both Buzz restore drills until their evidence is no more than nine
   days old.
4. In a separately authorized window, force power off, wait two minutes, power
   on, and require the verifier's operational-return verdict within ten minutes.
5. Run one missing-pool recovery exercise only with a fixture or safely detached
   test mount; do not manufacture a live pool fault for acceptance.
6. Update the root proposal/index with the exact commits, elapsed time,
   component verdicts, and restore-evidence timestamps.

Rollback is explicit: boot the prior Nix generation and restore the prior exact
Servarr pin. A missing data pool never triggers OS rollback. Stop the rollout on
an unclean checkout, ambiguous mount identity, missing console, stale restore
proof, or a verifier that emits values.

### Scenario coverage

| Behavior | First failing seam | Closing slice |
|---|---|---|
| Complete forced-power return | Fixture verdict, then staffed witness | 4, 5 |
| Per-stack storage matrix and lookalike mount | Storage fixtures | 2 |
| Reachable degraded boot | Module/orchestration fixtures | 2 |
| Offline known desired state and invalid-pin rejection | Exact-revision fixtures | 3 |
| Late-pool recovery and repeat safety | Recovery fixtures | 4 |
| MicroVM storage boundary | Module fixture and dry build | 2 |
| Exact, value-free component verdict | Verifier fixtures | 4 |
| Separate recovery readiness | Verifier fixtures | 4 |
| State classification and fresh restore proof | Servarr contract test, live gauges | 1, 5 |
| Read-only repeated verification | Verifier fixture run twice | 4 |

### Review and rollback gates

- **Security:** machine-bound pin, exact dataset identity, value-free output,
  and fail-closed invalid state.
- **Reliability:** no global storage dependency, bounded ten-minute verifier,
  explicit late recovery, prior generation/pin retained.
- **Compatibility:** shared exact-revision tests pass for all existing consumers.
- **Operations:** local console precedes activation; forced power requires its
  own authorization; verifier and recovery remain separate commands.
- **Simplicity:** one producer contract and one host tool; no watcher, new
  service manager, automatic import, or duplicate backup system.

## Frontier

Ready for implementation with a 10-minute operational-return deadline measured
from power-on. Final live acceptance needs a staffed maintenance window and the
approved forced-off, two-minute-off, power-on sequence. The optional hardware
branch still needs one fact: whether Kepler has a manageable UPS.
