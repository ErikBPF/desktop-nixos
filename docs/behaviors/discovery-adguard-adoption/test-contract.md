# Discovery AdGuard in-place adoption test contract

**Status:** Draft; fixtures and read-only preflight precede live approval

## Test boundary

Fixture tests and the planner never contact Discovery. Live inventory and
preflight are read-only and run only through documented `just` recipes.
Stopping services, creating production protection artifacts, pulling Servarr,
recreating containers, rollback, and reboot belong to a separately approved
execution phase.

## Fixture matrix

| Fixture | Expected result |
|---|---|
| Exact running declared AdGuard/exporter pair | Read-only inventory succeeds; no lifecycle action |
| Stopped container during current baseline phase | Halt; a later post-stop phase requires its own model |
| Missing, duplicate, foreign-project, unlabeled, or unknown container | Halt |
| Compose owner, service, project, network, or working-directory mismatch | Halt |
| Exact pre-adoption tag-only reference with RepoDigest matching desired pin | Accept only in pre-adoption mode |
| Other tag-only or already-changed runtime reference | Halt |
| Desired immutable render, matching live RepoDigest, and exact image ID | Accept |
| Exact `networking_adguard_work` at `/opt/adguardhome/work` | Accept for in-place adoption |
| Volume owner, mode, driver, mountpoint, reference, or mount-target drift | Halt |
| `discovery_adguard_work` present | Protect; never select, reuse, or delete |
| Render maps external logical volume to `networking_adguard_work` | Accept |
| Render derives a project-prefixed volume or creates a new volume | Halt |
| Bind configuration lacks snapshot coverage | Halt |
| Baseline contains credential, environment, query content, or client data | Reject output |
| Inventory changes after authorization | Reject execution |
| Second completed run with identical state | No pending action |

## Current deterministic preflight assertions

- The artifact is `preflight-only`, has `approval_ready: false`, and names the
  missing backup/restore and secondary-DNS-or-waiver blockers.
- It binds stable runtime/storage/render identity and semantic probe status;
  volatile counters remain observation evidence and do not change its hash.
- It has no approval scope, execution mode, rollback action, or evidence-path
  authority.

## Later approval-ready manifest assertions

- The approval scope is exactly `adguard` and `adguard-exporter`.
- The manifest binds exact full container IDs, immutable image references and
  image IDs, labels, networks, mounts, physical volume identity, bind boundary,
  Servarr commit, rendered Compose hash, baseline schema, ordered phases,
  rollback boundary, and evidence paths.
- Canonical JSON produces the same SHA-256 for equivalent input regardless of
  discovery order.
- Any bound-field drift invalidates authorization.
- Reports contain no secret values, environment, credential hashes or sizes,
  full API/YAML export, query contents, or client identifiers.
- No planned command contains broad prune, volume removal, dataset destruction,
  parent deletion, production-volume creation/copy/rename, Terraform mutation,
  SWAG recreation, or remote editing.
- The manifest does not select `discovery_adguard_work`, P0/P1 evidence,
  snapshots, archives, backups, or unrelated legacy resources for cleanup.

## Protection and rollback fixtures

The disposable protection fixture must prove this exact order:

1. Persist ledger.
2. Stop fixture service and dependent exporter.
3. Snapshot bind state.
4. Archive named-volume state and checksum it.
5. List/read the archive.
6. Restore to a non-live target.
7. Compare content, ownership, mode, ACLs, and xattrs.
8. Render and verify the same external physical mapping.
9. Recreate fixture services without data copy.
10. Run smoke gates and persist rollback evidence.

Inject failure at every step. No later step may run after failure. Snapshot,
archive, checksum, restore target, ledger, and journals remain retained. Tests
must prove rollback uses fixed arguments and never evaluates a ledger command.

## Baseline and live smoke contract

Before and after recreation, and again after reboot, record and compare:

- LAN A and AAAA resolution;
- one fleet rewrite;
- one external lookup through the intended upstream behavior;
- one configured blocked-domain response;
- AdGuard API health;
- filter count and stable value-free identities;
- query-log and statistics availability without query payloads;
- rewrite and user-rule counts or stable value-free identities;
- exporter health and representative metrics;
- container health, restart count, exact project/service/owner labels, immutable
  image identity, networks, `/opt/adguardhome/work` volume source, and
  `/opt/adguardhome/conf` bind source;
- relevant startup logs without environment or credential output.

Tests must define allowed volatile fields such as timestamps and counters.
Unexplained semantic differences halt; tests must not normalize away failures.

## Secondary DNS interlock

P2 read-only tests do not require P3 mutation. P2 live execution must fail
closed unless evidence proves a LAN-reachable secondary resolves both fleet and
external names while AdGuard is stopped. A public resolver is not sufficient.

The only alternative is an explicit, manifest-bound maintenance waiver naming
the absent secondary, bounded downtime, IP-based recovery path, prefetched
artifacts, and operator acceptance. The waiver authorizes no P3 infrastructure
change and does not satisfy P3 completion.

Fixtures cover secondary success, public-only fallback rejection, unreachable
secondary, fleet-only or external-only partial resolution, and exact waiver
acceptance/rejection.

## Live read-only gate

Before requesting approval, fresh output must prove:

- the exact runtime and storage inventory matches fixtures;
- both images are immutable;
- the external Compose render resolves to `networking_adguard_work` without
  creating another volume;
- bind snapshot and named-volume archive plans cover all P2 state;
- baseline probes pass and their evidence is value-free;
- recovery inputs are local/prefetched and do not depend on AdGuard DNS;
- secondary outage evidence or the exact waiver is present;
- manifest SHA-256 is deterministic and a changed inventory is rejected.

The coordinator stops here for explicit approval. Read-only success is not P2
completion.

## Live success gate

After approved execution, retain fresh evidence for the exact phase order,
protection/restore comparison, same physical volume, new declared container
identities, immutable images, complete smoke comparison, and rollback evidence.
Then reboot Discovery through the documented recipe and repeat runtime,
storage, DNS, API, exporter, log, and secondary-resolution gates.

P2 passes only when a final read-only planner returns no pending action. The
legacy physical volume and all protection evidence remain retained for P5/P9;
their deletion is outside this contract.
