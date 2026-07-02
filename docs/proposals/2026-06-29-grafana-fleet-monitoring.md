# Fleet observability — complete the Grafana monitoring stack

**Status:** In progress — forks decided + Phase 1 implemented 2026-07-01 (see
below); Phase 2 blocked on the cadvisor name-metric gap. Phase 3 metrics are
**half-live** (audit 2026-07-02): kube-state-metrics + kubelet cAdvisor flow
into the discovery Prometheus via homelab-gitops `alloy-metrics` (`b0773ea`);
control-plane scrape, traefik metrics, and all k8s alert rules still missing.
See "Audit findings (2026-07-02)" below.
**Date:** 2026-06-29
**Audience:** Maintainers of `desktop-nixos` + `servarr`

**Decisions (erik, 2026-07-01):**

1. **Container-alert scope → curated critical set** (dashboard for the rest).
   NOTE: the curated container-down rules were attempted earlier and dropped —
   compose hosts emit no name-labeled cadvisor series (rootless podman socket
   perms on kepler/orion; discovery docker not emitting names). They are
   tombstoned in `rules.yaml` (`deleteRules`) until the pipeline is fixed;
   that fix is the real Phase 2 work.
2. **k3s metrics path → (b) Alloy in-cluster → remote_write** to the discovery
   Prometheus (single Prometheus/Grafana, matches the fleet push pattern).
3. **Severity routing → split**: critical → `#incidents` (1h repeat),
   info → `#deploys`, warning falls through to root (`#incidents`, 4h) —
   provisioned in `policies.yaml` + `contactpoints.yaml`.

**Phase 1 status (2026-07-01, servarr `0a0fb96`):** `host-health` group live in
`provisioning/alerting/rules.yaml` — host-alloy-down (critical), memory <5%,
OOM-kill, fleet disk-fill (retires `disk-fill-24h` via tombstone), plus
load-per-core, swap-thrash, and inode-exhaustion. Also fixed never-firing
`lt 0` evaluators on host-memory-critical / voyager-disk-low. Deploy =
pull-servarr discovery + recreate grafana; then force-fire per the Verify
section.

## Context

The ntfy→Discord migration and the Healthchecks→textfile dead-man's-switch work
(2026-06-29) put the **alerting** layer in order but exposed how thin the
**coverage** is: only two alert rules exist (disk-fill, restic backup liveness)
against a fleet that already ships rich metrics. This RFC scopes turning the
existing telemetry pipeline into actual monitoring — host health, per-host
container stacks, and the k3s cluster — all alerting to Discord.

It is an **audit + gap-closure** RFC, not greenfield: the pipeline already
exists and carries most of the data. The work is alert rules, coverage
confirmation, k3s wiring, and dashboards.

## Current state (as-built, verified 2026-06-29)

**Pipeline.** Two Alloy layers feed one Prometheus + Loki + Grafana on
discovery:

- **NixOS fleet Alloy** (`modules/services/alloy.nix`, all 7 hosts) — `unix`
  exporter (host metrics) + systemd journal → `remote_write`/`loki.write` to
  discovery. Now also a **textfile collector** (`/var/lib/node-exporter-textfile`)
  for dead-man's-switch metrics.
- **servarr Docker Alloy** (`machines/<host>/config/alloy/config.alloy` on
  discovery/kepler/orion/voyager) — Docker/podman container **logs** → Loki and
  container **metrics** via the `cadvisor` exporter (`podman.sock`) → Prometheus.

Remote hosts reach discovery over Tailscale; metrics arrive by `remote_write`
(Prometheus' own scrape list is just self + alloy-self + loki — the per-host
node-exporter scrape jobs were intentionally removed in favour of push).

**Alerting.** Grafana unified alerting → **Discord** contact point (`#incidents`),
default notification policy. Rules today: `disk-fill-24h`, `restic-tofu-state-stale`.

**Dashboards.** `homelab-overview.json`, `kubernetes/k8s-cluster-health.json`
exist (feed-completeness unverified).

**k3s (kepler).** Per the kepler-k3s observability reference: Alloy logs→Loki,
host metrics→Prometheus, etcd metrics→`/bulk`. In-cluster workload/control-plane
metrics (kube-state-metrics, kubelet cAdvisor, apiserver/scheduler/cm) are the
suspected gap — the dashboard exists but may be partially unfed.

### Coverage matrix (audited 2026-07-02, live Prometheus queries)

| Host | Host metrics | Container metrics | Logs | Alerts today |
|------|:---:|:---:|:---:|---|
| discovery | ✅ unix | ✅ cadvisor (no `name` label) | ✅ | host-health, disk, backup, openbao |
| kepler | ✅ unix | ✅ cadvisor (no `name` label) | ✅ | host-health group (fleet-wide) |
| orion | ⚠️ `up==0` (see audit) | ✅ cadvisor (no `name` label) | ✅ | host-health group (fleet-wide) |
| pathfinder | ❌ absent ≥7d (see audit) | n/a | ❓ | host-health group (fleet-wide) |
| laptop | ✅ unix | n/a | ✅ | host-health group (fleet-wide) |
| archinaut (RPi3) | ❌ deliberate (alloy omitted, ~260 MB RSS) | n/a | ❌ | — |
| voyager | ✅ node-exporter scrape | n/a | n/a | scrape-down, disk, restic-check |
| k3s cluster | ✅ KSM (3.7k series) + kubelet cAdvisor pods | ❌ control-plane, ❌ traefik | ✅ | — |

### Audit findings (2026-07-02)

Live issues found while auditing the matrix:

1. **orion `up{job="integrations/unix"} == 0`** — host is up (its servarr
   Alloy pushes cadvisor fine) but the NixOS fleet Alloy's unix-exporter
   scrape fails. `host-alloy-down` should be firing; investigate + fix.
2. **Absent-host hole.** pathfinder has emitted nothing for ≥7 days and no
   alert fired: `host-alloy-down` matches `up == 0`, but a host that vanishes
   from the vector produces no series (and no NoData while other hosts keep
   the query non-empty). The "or series `absent` per host" bullet in section A
   was never implemented. Fix: per-host `absent_over_time()` rules for
   **always-on** hosts only (kepler, orion — voyager already covered;
   pathfinder/laptop are workstations that legitimately power off; discovery
   monitoring itself is the accepted SPOF).
3. **remote_write lag ~5–15 min** observed (instant queries empty while
   `-10m` evaluations return data). Alert `for:` + relative windows must
   tolerate this; prefer ≥15 m lookbacks for push-fed rules.
4. **Traefik "gap" is not a bug** (diagnosed 2026-07-02): the scrape is fully
   healthy (`up{job="traefik"} == 1` continuously, 21.7k samples/14d). Traefik
   registers `traefik_entrypoint_requests_total` & co. **lazily per label
   combination** and they reset on pod restart — the lab ingresses have simply
   had zero traffic since the c91172d validation curls (2026-06-21). Use
   `... or vector(0)` in panels; alert on `up{job="traefik"}`, never on
   request-counter presence. Optional: a periodic probe against a lab ingress
   keeps the series registered and validates LB→NodePort→router end-to-end.
5. **k3s pods restart every few hours-days** (exit 255, reason Unknown; 16–32
   restarts/12d fleet-wide in the cluster) — the microvm nodes themselves
   appear to reboot. Not what suppressed the traefik counters, but worth a
   separate investigation.
6. **archinaut** — Alloy intentionally omitted
   (`modules/hosts/archinaut/default.nix`); section A's "lightweight external
   check" remains undecided/unbuilt.
7. **orion root cause** (diagnosed 2026-07-02): amdgpu **SMU firmware hang**
   (since 19:43 same day, after the 19:21 reboot) wedges node_exporter's hwmon
   collector in an uninterruptible sysfs read → `/metrics` never returns →
   `up==0`; cadvisor in the same Alloy process is unaffected. Unrecoverable
   from userspace (D-state victims incl. a stuck torch CUDA check) — needs a
   reboot, which folds into the pending b3daafc deploy-rs-boot window.
   Hardening option: exclude the hwmon collector on GPU hosts in
   `modules/services/alloy.nix` so a firmware wedge degrades one collector
   instead of killing all host metrics.

## Goals

1. **Host health + resources** — every host: up/down, CPU saturation, memory
   pressure/OOM, disk (have), inode/swap, load. With alerts + a per-host view.
2. **Deployed stacks per host** — container up/down, crash-loop (restart rate),
   failed healthcheck, per-container CPU/mem vs limit. Docker (discovery) +
   podman (kepler/orion).
3. **k3s cluster** — nodes Ready, workloads (deployments/statefulsets/pods),
   control plane + etcd, PVC/CSI (kepler NFS), ingress, cert expiry, job/cronjob
   failures.

All alerting routes to Discord (the `#incidents`/`#deploys` split already built).

## Gaps → proposed work

### A. Host health
Metrics exist; **alert rules don't**. Add (PromQL → Grafana rules → Discord):
- node down: `up{job="integrations/unix"} == 0` or series `absent` per host.
- CPU saturation (sustained), load-per-core, memory available < threshold,
  OOMKill events (`node_vmstat_oom_kill` delta), swap thrash, inode exhaustion.
- archinaut: confirm Alloy runs (or use a lightweight external/host check given
  RPi3 memory); don't force the full exporter if it hurts reliability.

### B. Container / stack health
`cadvisor` exporter exists on discovery (confirm kepler/orion). Add:
- container down: `time() - container_last_seen > grace` for a tracked set.
- crash-loop: `rate(container_start_time_seconds[15m])` / restart count.
- unhealthy: Docker healthcheck status (needs a healthcheck-state source —
  cadvisor doesn't expose it; may need a small docker-state exporter or compose
  healthcheck → log-based alert).
- resource: per-container mem vs `mem_limit`, CPU throttling.
- **Decided (2026-07-01)**: **curated critical set** (swag, adguard, litellm,
  postgres, …) + a dashboard for the rest. Blocked on the cadvisor
  name-metric gap (see Decisions above).
- per-host **stack dashboard** (container grid: state, cpu, mem, restarts).

### C. k3s cluster
- **Decided (2026-07-01) — metrics path: (b) Alloy in-cluster** scraping
  cluster components → `remote_write` to the discovery Prometheus (matches the
  existing push pattern; single Prometheus, single Grafana).
  **Implemented 2026-07-02-ish** in homelab-gitops (`platform/alloy-metrics`,
  `platform/kube-state-metrics`, commits `b0773ea`/`c91172d`) — KSM + kubelet
  cAdvisor verified flowing into the discovery Prometheus.
- Still to scrape: control-plane (apiserver/scheduler/controller-manager —
  `apiserver_request_total` absent), kubelet's own metrics (`kubelet_*`
  absent), ingress controller (traefik broken, see audit), CSI/NFS.
- Alerts: node `NotReady`, pod `CrashLoopBackOff`, deployment replicas
  unavailable, PVC `Pending`, job/cronjob failed, etcd unhealthy, cert expiry,
  control-plane down. (kube-prometheus ships a vetted rule set — port the subset
  that fits.)
- Feed `k8s-cluster-health.json`; confirm datasource/labels match.

### D. Alert routing & dashboards
- Severity labels → notification policy: **decided (2026-07-01)** — critical →
  `#incidents` (1h repeat), info → `#deploys`, warning → root/`#incidents`
  (4h). Provisioned in `policies.yaml`/`contactpoints.yaml`; the
  `DISCORD_WEBHOOK_DEPLOYS` pre-deploy gate was verified live (var present in
  the grafana container env).
- Dashboards: a **fleet alert overview** (firing/pending by host) + the per-host
  stack and the fed k8s dashboard. Link runbook snippets in alert annotations.

## Non-goals / accepted limits

- **Host-death SPOF.** Prometheus/Grafana run on discovery and monitor
  discovery; if discovery dies, alerting dies. An external watchdog was
  **declined** (2026-06-29) — documented, not solved here.

### Deferred plans

- **Cross-host liveness ping.** Instead of (or alongside) an external watchdog,
  have each host's Alloy / a tiny systemd timer **ping a peer** (e.g. kepler and
  orion each post a heartbeat that discovery alerts on if it stops, and at least
  one non-discovery host watches discovery's heartbeat). A peer noticing a
  missing heartbeat is the cheapest on-prem mitigation for the host-death SPOF
  without an off-box dependency. Mechanism TBD (textfile heartbeat scraped
  cross-host via the existing remote_write mesh, or a Discord push from a peer
  on missed ping). Deferred — not scheduled.
- Long-term metric/log retention & cardinality budget (Prometheus TSDB sizing,
  the known Loki cardinality item) — track separately; note any high-cardinality
  labels new scrapes introduce (k8s labels especially).

## Phasing

1. **Alert rules on existing metrics** (host-down, OOM, mem, curated
   container-down) — cheap, high value, **no new infra**. Mirrors the
   `disk`/`backups` rule-group pattern in `provisioning/alerting/rules.yaml`.
2. **Container coverage** — confirm cadvisor on kepler/orion; per-host stack
   dashboard; crash-loop/unhealthy alerts.
3. **k3s** — stand up kube-state-metrics + cluster scrape (path per `TODO`),
   workload alerts, feed the k8s dashboard.
4. **Polish** — fleet alert-overview dashboard, runbook links, severity routing.

## Verify (per phase)

- Force each alert: `up==0` (stop alloy), stop a curated container, `kubectl
  drain` a node → fires in Discord within the eval window; resolves on recovery.
- Dashboards render live data for every host in the matrix.
- No alert storms from flapping/low-signal rules (tune `for:` + thresholds).

## Links

- Builds on `implemented/2026-06-20-telemetry-hardening.md`,
  `proposals/2026-06-29-discovery-resilience-fixes.md`,
  `reference/kepler-k3s-platform-status.md`.
