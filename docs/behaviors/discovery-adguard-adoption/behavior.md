# Discovery AdGuard in-place adoption

**Status:** Draft P2 contract; read-only preparation only

## Outcome

Adopt Discovery's existing `networking_adguard_work` Docker volume explicitly
without copying or renaming its data. AdGuard and its exporter return with the
same DNS behavior and state under the Servarr-owned networking stack. The
physical volume, migration protections, and evidence remain retained.

## Scope

P2 covers the `adguard` and `adguard-exporter` services, the existing
`networking_adguard_work` physical volume mounted at
`/opt/adguardhome/work`, and the bind-mounted AdGuard configuration at
`/opt/adguardhome/conf`.

P2 does not create or adopt `discovery-adguard-work`, copy data to a canonical
volume, change AdGuard API configuration, import or apply Terraform, change
DHCP, alter SWAG, delete a container or storage object, or clean up retained
evidence. Those concerns remain in P3, P4, P5, or P9.

## Current read-only slice

Before any workload mutation:

1. Record a value-free inventory of the exact containers, Compose labels,
   owner, state, restart count, networks, image references and IDs, mounts, and
   deployed Servarr revision.
2. Require immutable desired digest pins for both AdGuard and its exporter.
   The pre-adoption runtime may retain its exact historical tag-only reference
   only when its unique repository digest matches the desired pin; the rendered
   replacement must use the tag-and-digest reference.
3. Inspect `networking_adguard_work` by exact physical name. Record its driver,
   scope, labels, mountpoint, size, mode, ownership, and references. Require its
   sole intended AdGuard mount to be `/opt/adguardhome/work` and require the
   reviewed `65534:65534` ownership contract. Ambiguity or drift halts.
4. Record the bind-mounted configuration source, filesystem boundary, size,
   mode, ownership, and snapshot coverage without reading credentials.
5. Capture a value-free behavior baseline: LAN A and AAAA queries, fleet
   rewrite, external lookup, configured blocked response, API health, filters,
   query-log and statistics availability, rewrites, user rules, and exporter
   metrics. Do not retain query contents, client identifiers, credentials,
   environment, or a full configuration export.
6. Render the proposed Servarr definition and prove it maps an external logical
   volume directly to the same physical `networking_adguard_work`. It must not
   create, select, or reference `discovery_adguard_work`.
7. Emit a deterministic, value-free, explicitly not-approval-ready preflight
   bound to the stable inventory, rendered Compose hash, and exact Servarr
   commit. It names the missing protection and secondary-DNS/waiver evidence;
   a changed stable live fact invalidates it.

The later approval-ready manifest must additionally bind exact ordered actions,
rollback boundary, evidence paths, and only `adguard` and `adguard-exporter`.

Read-only collection and fixture testing may proceed now. The preflight has no
approval scope or execution mode. These actions do not stop a
service, pull a deployment revision, create a snapshot or archive, or authorize
the later adoption.

## Mutation boundary

Mutation requires all of the following:

- the Servarr leaf change is tested, committed, pushed, and named in the
  manifest;
- immutable images are already available before DNS downtime;
- a fresh preflight matches the reviewed manifest exactly;
- the operator approves the manifest SHA-256 and the exact `adguard` and
  `adguard-exporter` resources;
- a LAN-reachable secondary resolver has passed fleet and external resolution
  probes while AdGuard is stopped, or the operator explicitly approves a
  bounded P2 maintenance waiver that acknowledges loss of fleet DNS and proves
  recovery does not depend on DNS.

The secondary-resolver requirement resolves the ordering tension between the
phased list, which places P3 after P2, and P3's requirement to provide fallback
before AdGuard maintenance. Recommended execution order is P2 read-only work,
then the P3 outage gate, then P2 mutation. This is a safety interlock, not early
P3 infrastructure mutation under P2 authority.

After approval, the fixed workflow must:

1. Persist the complete ledger before stopping anything.
2. Stop only AdGuard and the dependent exporter; SWAG and unrelated networking
   services remain running.
3. Create a read-only Btrfs snapshot covering the bind configuration.
4. Archive the stopped `networking_adguard_work` volume, checksum it, prove it
   can be listed and read, restore it to a non-live target, and compare content
   and metadata before recreation.
5. Pull the approved Servarr revision only through the documented `just`
   channel and prove the rendered external mapping still names the same
   physical volume.
6. Recreate only AdGuard and its exporter without copying state.
7. Repeat the complete baseline and verify exact image, labels, mounts, health,
   restart behavior, logs, and metrics.

No command may prune, remove, rename, create, or copy a production volume. No
remote file is edited. Existing Restic coverage does not replace the local
snapshot, archive, restore, and compare gate.

## Rollback and retention

Rollback restores the previous published Servarr mapping and recreates the
prior AdGuard/exporter owner against the same untouched physical volume. It is
a fixed, hash-bound action; stored command text is never evaluated. A rollback
drill or execution is mutating and must be included in the approved manifest or
approved separately.

Failure stops further action. The source volume, bind snapshot, archive,
checksum, restore comparison, ledger, manifest, journals, and both Servarr
revisions remain retained. Nothing is cleanup-eligible merely because P2
passes.

## Completion

P2 closes only after the approved in-place recreation passes all DNS, API,
state, exporter, identity, mount, log, and rollback-evidence gates, Discovery
reboots through the documented recipe, and the same gates pass again. Reboot is
required by the proposal's global live-stack and migration gates even though
the short P2 phase list omits it.

The final read-only run must report the same physical volume, explicit external
mapping, no pending P2 action, and no mutation of `discovery_adguard_work`.
Deletion and canonical migration remain separately blocked.
