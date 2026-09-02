# Kepler k3s etcd I/O degradation — 2026-08-30

**Status:** Mitigated; cluster recovered, writer attribution and storage redesign remain open.

This record separates observed facts from the leading explanation. It does not
authorize a restart, filesystem repair, Argo sync, storage change, or PV
deletion.

## Impact and timeline

All times are UTC on 2026-08-30.

- At 02:46, `w-2` was explicitly restarted through systemd. Its mount and CSI
  warnings are expected restart fallout, not evidence of the later cause.
- Around 03:09, all three k3s server processes restarted within 26 seconds.
  Their MicroVM services had remained active since August 27, so this was not a
  simultaneous MicroVM reboot.
- During the outage, the Kubernetes API became unavailable and workloads
  emitted transient Secret, ConfigMap, service-account, NFS CSI, and probe
  failures.
- A similar etcd latency burst recurred around 03:28.
- By the end of triage, all six nodes were Ready, controllers were available,
  PVCs were bound, ESO stores were valid, and the API `/readyz` checks passed.

## Confirmed evidence

- etcd WAL fsync p99 reached 0.76–1.26 seconds; backend commit p99 reached
  0.80–1.25 seconds. Logs also recorded slow reads, writes, and delayed
  `ReadIndex` responses.
- The four `fast-pool` RAIDZ1 SSD members each reached roughly 32–34 MB/s of
  physical writes with queue pressure during the degraded window.
- Every control-plane root image, including each embedded-etcd data directory,
  lives below `/fast/microvms` on that one pool and physical host.
- Both ZFS pools were ONLINE. No scrub or resilver was active. Podman block
  output was near zero, so neither a failed pool nor the observed Podman
  workloads explain the write burst.
- The exact process, MicroVM, NFS client, or host job producing the writes was
  not captured. Do not assign a writer without a fresh sample.
- A healthy-state `just diagnose-kepler-io` proof at 03:46 attributed about
  5.1 MB of the three-second process delta to `microvm@w-3.service`, about
  1.0–1.1 MB to each control-plane guest, and smaller writes to journald/NFS.
  The three interval samples were only 2.73–3.20 MB/s pool-wide. This proves
  the recipe can distinguish guests; it does not identify the earlier
  32–34 MB/s/member incident writer.
- Kepler's root Btrfs still reports `inode mode mismatch`. This is a separate
  serious filesystem risk; available evidence does not correlate it with the
  `fast-pool` event. Automatic Nix GC and upgrades are already held.

## Leading explanation, not yet root cause

The observed fast-pool queueing is sufficient to explain etcd missing latency
budgets and losing timely quorum communication. Because all three etcd members
share the same RAIDZ1 pool and host, one storage stall affects every member at
once. This is a correlated failure domain, despite having three logical etcd
members.

The unexplained writer is still the root-cause gap. Treat “storage contention
starved etcd” as the incident mechanism, not proof of which workload initiated
it.

## Immediate containment and capture

1. Avoid bulk writes, image moves, model-cache churn, and backup jobs on
   `/fast` while etcd latency is elevated.
2. During the next recurrence, run `just diagnose-kepler-io`. It takes three
   one-second pool samples and ranks process write-byte deltas without printing
   process arguments or secret material. A `microvm@<node>.service` cgroup
   identifies a guest; a host service cgroup identifies a host-side writer.
3. Correlate the sample with the `etcd-control-plane` dashboard and
   `journalctl` through existing documented diagnostic recipes.
4. If service recovery is required, preserve etcd quorum. Never restart all
   control-plane guests together.

## Structural remediation decision

The preferred fix is to move control-plane/etcd state onto dedicated,
low-latency physical storage that does not contend with workers, NFS, model
caches, or bulk jobs. Merely creating another dataset on `fast-pool` does not
remove the shared queue or failure domain.

Before implementation, choose and benchmark one concrete layout:

- dedicated devices for control-plane state, with failure domains independent
  enough that one host/pool stall cannot pause all three members; or
- accept the single-host sandbox availability ceiling and isolate/prioritize
  control-plane I/O on dedicated devices, while retaining snapshots and a
  tested restore procedure.

Do not add a ZFS SLOG, tune etcd timeouts, or weaken alerts as a substitute for
measured storage latency. Those can hide or relocate the failure without
removing contention.

## Other bounded corrections

- `diagnose-kepler-kernel` now queries the existing Loki ingress instead of the
  retired `discovery:3100` endpoint. No Loki exposure or NetworkPolicy change
  is needed.
- The GitOps monitoring values attach `cluster="homelab"` to the kubelet
  `/metrics` scrape, fixing the label mismatch that made `KubeletDown` fire
  while kubelets were up.
- Only `PrometheusNotConnectedToAlertmanagers` is disabled: this deployment
  intentionally has Alertmanager disabled. `KubeletDown` remains enabled.
- `DNSConfigForming` remains a follow-up. Source does not yet establish which
  guest resolver inputs create more than three nameservers. Capture
  `/etc/resolv.conf` and resolved/networkd state on every guest through a
  documented read-only recipe before capping the list; preserve fleet/local
  domain resolution rather than replacing it with public-only resolvers.

## Explicit no-live-repair warning

Do not run `btrfs check --repair`, `zpool scrub`, a pool/dataset migration,
etcd restore, simultaneous guest restart, or manual Argo reconciliation as an
incident diagnostic. Back up Kepler, then inspect the root Btrfs filesystem
offline and read-only in a separate approved maintenance window.

## Verification and deployment gates

Repository checks:

```bash
# desktop-nixos
pytest -q tests/grafana-alert-ops/test_alert_recipes.py
just docs-check
just lint
just fmt-check

# homelab-gitops
just test
```

After review and merge, only the GitOps monitoring change requires cluster
reconciliation. Pin the reviewed commit; do not sync the currently drifting
root application:

```bash
cd /path/to/homelab-gitops
SHA="$(git rev-parse HEAD)"
just sync "$SHA" monitoring
```

The `justfile` and documentation changes require no NixOS deployment. After
monitoring sync, verify `KubeletDown` is absent when kubelet targets are up and
that `PrometheusNotConnectedToAlertmanagers` no longer renders.
