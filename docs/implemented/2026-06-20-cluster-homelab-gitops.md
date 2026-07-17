# `homelab-gitops` — a production-mimicking platform layer for the kepler k3s cluster

**Date:** 2026-06-20
**Status:** Implemented (2026-07-02 audit) — the skeleton became the live
`homelab-gitops` sister repo. It reached 14 Argo CD applications during initial
bring-up; Harbor then moved to Discovery and in-cluster Vault was replaced by
OpenBao@Discovery. Current state is 11 child apps plus the root app (12 total):
Argo self-management, ESO AppRole, csi-driver-nfs fast/slow, Traefik default
IngressClass, KEDA, Jaeger+OTel, kube-state-metrics/alloy-metrics, and demos.
As-built record:
[`reference/kepler-k3s-platform-status.md`](../reference/kepler-k3s-platform-status.md).
Remaining `TODO(erik)` items below are enhancements, not gaps: external-dns
provider choice, Jaeger storage/dual-sink tracing, Harbor blob-storage policy
on the cluster side, multi-cluster ApplicationSet patterns.
**Owner:** erik
**Scope:** a NEW sister repo (servarr-style: symlink under `references/repos/`,
`just` recipes) that adds a production-grade platform layer to the kepler k3s
cluster. **Not NixOS-deployed** — applied to the cluster like servarr's docker
stacks. Telemetry hardening of the existing stack is separate —
[`2026-06-20-telemetry-hardening.md`](../implemented/2026-06-20-telemetry-hardening.md).

> **Intent (changed from v1): this is a LAB to MIMIC PRODUCTION**, not a minimal
> homelab. "Overkill" is the point — Traefik, Harbor, external-dns, ESO+Vault,
> Jaeger/OTel, KEDA are in scope precisely to reproduce prod patterns and keep
> the skills warm. The single-host reality still caps **storage replication**
> (no Longhorn) but not the control-plane tooling.

## 1. Deploy model — sister repo on the servarr strategy (NOT Nix)

The new platform components are **not** baked into the NixOS flake. The repo
mirrors servarr: a git repo, symlinked at `references/repos/homelab-gitops`,
with `just` recipes; applied to the live cluster.

- **Engine: Argo CD** (prod-realistic GitOps: drift detect, self-heal, UI),
  **bootstrapped once via a `just` recipe** — not Nix:
  1. `just bootstrap` → `helm install argocd argo/argo-cd --version 9.6.0` into
     ns `argocd`.
  2. `kubectl apply` a root **app-of-apps** Application → repo's `apps/`
     (`syncPolicy.automated {prune, selfHeal}`). (Argo ≥2.5 has no auto-root —
     this manual seed is intentional.)
  3. Argo pulls everything else, incl. a child Application that manages **its own
     Helm release** ("Argo manages Argo") → upgrades become a committed bump.
  Daily loop: edit → `git push` → optional `just sync` (`argocd app sync root`)
  — same ergonomics as servarr's "drop a stack dir, run a recipe."
- **The substrate stays in NixOS** (unchanged, no risky migration): k3s,
  `_k3s-node.nix`, networkd, NAT, the nginx L4 LB, PSA admission, etcd snapshots,
  **and the existing `autoDeployCharts` ingress-nginx + Alloy**. GitOps owns the
  *new* platform/workload layer; Nix owns the bootstrap-critical substrate. No
  helm-controller↔Argo overlap (they manage disjoint objects).

> Reversal from v1: the earlier "Nix seeds Argo + migrate ingress-nginx/Alloy
> out" handoff is dropped per direction — too much risk for no gain. New things
> go in the GitOps repo; existing Nix-deployed things stay put.

## 2. Recommended stack (prod-mimic; version-pinned at research time)

| Layer | Pick | Chart / version | Notes |
|---|---|---|---|
| GitOps | **Argo CD** | `argo-cd` 9.6.0 (appVer v3.x) | bootstrapped via `just`, self-managing |
| Ingress | **Traefik** (mimic prod) | `traefik` chart | **replaces** ingress-nginx as the default IngressClass; reuses NodePort 30443 so the L4 LB is unchanged. IngressRoute/middleware CRDs |
| Storage RWX **fast** | csi-driver-nfs → `/fast/k8s` | `csi-driver-nfs` 4.12.0 (kube-system) | StorageClass `nfs-fast` → **fast-pool** (SSD RAIDZ1) |
| Storage RWX **slow** | csi-driver-nfs → `/bulk/k8s` | same driver, 2nd SC | StorageClass `nfs-slow` → **bulk-pool** (HDD) |
| Storage RWO | k3s **local-path** (default) | built-in | ephemeral/scratch |
| Registry | **Harbor** (mimic prod) | `harbor` chart | full: RBAC, Trivy scan, replication, proxy-cache. ~4GB min + postgres/redis |
| Secrets | **ESO → in-cluster Vault** | `external-secrets` 2.6.0 + `vault` 0.33.0 | AppRole over cluster DNS (see §5) |
| Autoscaling | **KEDA operator** | `kedacore/keda` 2.20.x | cron + prometheus scaler (→ external Prom) |
| Metrics | kube-state-metrics + node-exporter (+ kubelet cAdvisor) | KSM / node-exporter charts | remote_write → discovery Prometheus |
| Tracing | **Jaeger** + **OTel Collector** | `jaeger` + `opentelemetry-collector` charts | OTel receives OTLP → exports to Jaeger; spans from instrumented apps |
| DNS | **external-dns** (mimic prod) | `external-dns` chart | provider: AdGuard webhook / Cloudflare / UniFi — `TODO` |

Two SCs are the "fast and slow NFS" ask; both via one `csi-driver-nfs` install,
distinct `StorageClass` objects pointing at different kepler exports.

## 3. Ingress — Traefik (prod-mimic)

k3s shipped Traefik; we disabled it for ingress-nginx. To mimic prod, bring
**Traefik back via GitOps** as a second `IngressClass` (IngressRoute CRDs,
middlewares, the dashboard) behind the same kepler L4 LB / a second NodePort.
- **DECIDED: Traefik replaces ingress-nginx** (becomes the default IngressClass).
  Scaffolded in `platform/traefik` (NodePort 30443 = LB target). Cutover: bring up
  Argo + Traefik, verify, then remove ingress-nginx from the Nix `autoDeployCharts`
  and repoint the argocd ingress to traefik. Superseded note: ~~run Traefik
  alongside ingress-nginx (two classes)?~~
- No `Service type=LoadBalancer` — expose via NodePort behind the kepler L4 LB,
  same as ingress-nginx (NodePort 30443).

## 4. Storage — fast + slow NFS

One `csi-driver-nfs` (4.12.0, into kube-system to inherit the PSA exemption — the
node plugin is privileged), two StorageClasses:
- **`nfs-fast`** → `fast-pool` (SSD RAIDZ1, ~1.2T free) via `/fast/k8s` —
  databases, registry blobs, latency-sensitive PVCs.
- **`nfs-slow`** → `bulk-pool` (HDD, ~12T free) via `/bulk/k8s` — media, backups,
  bulk RWX.
- **`local-path`** stays the default SC for ephemeral/scratch RWO.
- **Skip Longhorn** — replicating across VMs on one physical disk = 3× waste,
  zero durability, runs degraded. ZFS gives integrity + snapshots already.
- **DONE (substrate):** both pools exist; `nas.nix` now exports `/fast/k8s` +
  `/bulk/k8s` rw,no_root_squash to `10.250.0.0/24` (dedicated subdirs so PVs don't
  mingle with the model cache / media). Nodes mount kepler at `10.250.0.1`.

## 5. Secrets — External Secrets Operator → in-cluster Vault (AS BUILT 2026-06-21)

> **Changed from the original plan (Vault-on-discovery).** Per direction, Vault
> runs **in-cluster on kepler** via GitOps, NOT as a discovery docker stack. ESO
> reaches it over **cluster DNS** (`vault.vault.svc:8200`) — no tailnet hop, no
> ACL grant, no discovery dependency, and it sidesteps the "pods can't resolve
> MagicDNS" problem entirely. Simpler + self-contained.

- **Vault deploy:** `platform/vault` (hashicorp/vault chart 0.33.0), **standalone**
  + **file storage on local-path** (node-local — single writer, no NFS-file-lock
  risk), **HTTP** (cluster-internal; TLS is a lab-acceptable skip). Injector off
  (ESO is the only consumer). Sync-wave -4 (before ESO).
- **Init + unseal:** one-time `vault operator init -key-shares=1 -key-threshold=1`;
  unseal key + root token stored in the `vault-init-keys` Secret (vault ns).
- **Auto-unseal:** a small `vault-unsealer` Deployment polls seal-status and
  unseals from `vault-init-keys` when sealed → survives vault-0 restarts. No KMS,
  so the unseal key is cluster-readable (inherent trade-off). Verified: killing
  vault-0 → auto-unsealed in ~30s, ESO reconnected.
- **Auth: AppRole.** `ClusterSecretStore vault-incluster` (**`external-secrets.io/v1`**
  — ESO serves v1, NOT v1beta1) with inline `role_id` + `secret_id` from the
  `vault-approle` Secret (external-secrets ns, seeded out-of-band via kubectl).
  Policy `eso-read` (read `secret/data/*`), KV v2 at `secret/`.
- **Consumer:** Harbor admin pw lives at Vault `secret/harbor`; a Harbor
  `ExternalSecret` recreates `harbor-admin-secret` (ESO-owned). Spell out ESO's
  server-defaulted fields (conversion/decoding/metadata/nullByte strategies +
  `deletionPolicy`) or Argo shows perpetual drift.

Follow-ups: wire Vault TLS; auto-unseal via a real KMS/transit if this grows
beyond a lab; seed `vault-init-keys` declaratively (sops) for clean rebuilds.

## 6. Registry — Harbor (prod-mimic)

Full Harbor (RBAC, Trivy vuln scanning, replication, proxy-cache) to reproduce a
production registry — deliberately heavier than zot.
- Footprint: documented min **2 CPU / 4 GB / 40 GB disk**; ships its own
  postgres + redis (give them PVs on `nfs-fast` + real requests + the 40GB floor).
- Use cases exercised: private images, Docker Hub **proxy-cache** (rate limits),
  image signing/scanning.
- **k3s mirror wiring:** no `services.k3s.registries` NixOS option — render
  `/etc/rancher/k3s/registries.yaml` via `environment.etc` in `_k3s-node.nix`
  (all 5 nodes), mirroring `docker.io` → Harbor proxy-cache project. Gotcha: the
  Harbor images themselves must not pull *through* Harbor (bootstrap from
  upstream/ghcr or bake).
- `TODO(erik)`: Harbor blob storage on `nfs-fast` vs node-local? (NFS works for
  Harbor unlike a bare OCI registry; confirm.)

## 7. Autoscaling — KEDA operator (now)

- `kedacore/keda` 2.20.x. Verify k8s 1.35 in its support window before install.
- **prometheus scaler works against our external Prometheus** (just needs the
  query URL + `TriggerAuthentication`) — confirmed compatible with push-out.
- **cron scaler** for scale-to-zero (free RAM on idle apps). CPU/mem scalers wrap
  HPA (need the k3s-bundled metrics-server — keep it).

## 8. In-cluster observability — exporters + OTel + Jaeger

- **Metrics:** kube-state-metrics + node-exporter (+ scrape kubelet cAdvisor) →
  the existing Alloy `remote_write` → discovery Prometheus. Closes the deferred
  metrics gap and lights up the k8s dashboards the telemetry RFC defers.
- **Tracing:** **OTel Collector** (OTLP receiver) → **Jaeger** (all-in-one with
  badger for a lab; cap its storage). Spans come from instrumented apps — the
  prod-mimic value is the pipeline; seed it with a demo app
  (otel-demo / hotrod) so it's not empty.
- `TODO(erik)`: Jaeger storage (badger all-in-one vs Elasticsearch/Cassandra —
  badger fine for a lab). Do traces also fan to discovery's Grafana (Tempo) or
  stay in Jaeger's own UI? (Jaeger UI is the prod-mimic choice.)

## 9. external-dns (prod-mimic)

Auto-manage DNS from ingress/service annotations to reproduce prod DNS
automation. Provider `TODO(erik)`: AdGuard (webhook provider) — keeps the
existing AdGuard source-of-truth; Cloudflare (public records); or UniFi. Note the
existing setup is NodePort behind L4 LB + AdGuard rewrites, so external-dns here
is for *learning the pattern*, not strictly needed.

## 10. Capacity — lab sizing (pack tight, tiny requests)

This is a **lab**, not a prod SLO target: set **minimal requests** (let pods
burst against limits, accept memory pressure) rather than the chart defaults.
Treat the upstream "minimums" as upper bounds — real idle is far lower:
- **Requests:** drop most to ~`32–64Mi`/`10–25m` (Argo controllers, ESO, KEDA,
  Traefik, KSM, OTel, Jaeger all idle small). **Explicitly cap OTel** — its chart
  sets only limits and silently reserves 2 GB/1 CPU otherwise.
- **Harbor** is the one real floor (docs: 2 CPU / 4 GB / 40 GB disk) — but for a
  lab, slim it: disable Trivy + Notary + chartmuseum, single replicas, and it
  drops well under that. Postgres/redis get small requests + a PV on `nfs-fast`.
- No node-pinning / anti-affinity needed at lab scale — let the scheduler pack
  both workers; revisit only if eviction churn shows up.

Net: the whole stack idles comfortably on 2×16 GB with room to spare; the 128 GB
kepler upgrade just removes any need to think about it.

## 11. Proposed repo layout (`homelab-gitops`, servarr-style sister repo)

```
homelab-gitops/
├── justfile                      # bootstrap / sync / app recipes (servarr ergonomics)
├── bootstrap/root-app.yaml       # app-of-apps; kubectl apply'd by `just bootstrap`
├── argocd/                       # Argo self-management (Chart.yaml→argo-cd 9.6.0)
├── platform/                     # cluster infra, sync-wave ordered
│   ├── vault/            (-4)    # in-cluster Vault (standalone) + auto-unsealer
│   ├── external-secrets/ (-3)    # ESO + ClusterSecretStore→vault.vault.svc
│   ├── csi-driver-nfs/   (-2)    # fast + slow StorageClasses (kube-system)
│   ├── traefik/          (-1)
│   ├── harbor/           (-1)
│   ├── keda/             ( 0)
│   ├── kube-state-metrics/ ( 0)
│   ├── otel-collector/   ( 0)
│   ├── jaeger/           ( 0)
│   └── external-dns/     ( 0)
└── apps/<app>/                   # workloads (+demo app emitting traces)
                                  # thin wrapper charts (Chart.yaml=1 dep+values)
```

Symlink: `references/repos/homelab-gitops → ~/Documents/erik/homelab-gitops`.
`just` recipes resolve via the symlink (like servarr). Sync-wave: secrets →
storage → ingress/registry → operators/observability → apps.

## 12. Coupling map (6th sister repo)

```
homelab-gitops (Argo CD + platform)   ← bootstrapped by `just`, NOT Nix
   Vault is IN-CLUSTER → no discovery/ACL dependency for secrets
   needs: registries.yaml Harbor mirror ▶ desktop-nixos _k3s-node.nix
homelab-iac: ACL grants for telemetry push (Loki/Prom) only; + any external-dns egress
servarr/discovery: Prometheus receives cluster metrics via remote_write
                   (alloy-metrics); Loki receives cluster logs (Alloy DS)
desktop-nixos substrate (k3s/LB/NAT/PSA, ingress-nginx+Alloy) STAYS as-is
```

Rule of thumb: land the leaf (homelab-gitops / servarr vault) → grant the ACL
(homelab-iac) → seed the secret / registries.yaml (desktop-nixos) → `just sync`.

## 13. Still-skip (even for prod-mimic, single host)

Longhorn (replication on one disk), Velero (etcd snapshots→`/bulk` + restic/k8up
of PV dirs cover DR), Descheduler (nothing to rebalance on one host). Everything
else the user named is **in**.

## 14. Decisions — `TODO(erik)`

- ~~Traefik alongside or replace?~~ **DECIDED: replace** (default IngressClass).
- ~~`nfs-fast` backing dataset?~~ **DECIDED: fast-pool SSD `/fast/k8s`** (slow =
  bulk-pool `/bulk/k8s`); exports added in `nas.nix`.
- external-dns provider: AdGuard webhook / Cloudflare / UniFi? (AdGuard is on
  discovery — **postponed** while discovery is busy.)
- Harbor blob storage: `nfs-fast` vs node-local?
- ~~Vault unseal automation?~~ **DONE: in-cluster Vault + a `vault-unsealer`
  Deployment** (polls seal-status, unseals from `vault-init-keys`). KMS/transit
  auto-unseal + TLS are post-lab hardening.
- Jaeger storage (badger vs ES); traces in Jaeger UI vs also Grafana/Tempo?
- Repo name + does it own future multi-cluster (ApplicationSet generators)?

## 15. Sources

argo-cd chart 9.6.0 + cluster-bootstrapping (argo-cd.readthedocs.io);
external-secrets v2.6.0 + Vault provider (external-secrets.io); Vault Raft +
AppRole (developer.hashicorp.com/vault); csi-driver-nfs 4.12.0 (kubernetes-csi);
Harbor prereqs 2 CPU/4 GB/40 GB (goharbor.io/docs/install-config); KEDA 2.20 +
prometheus scaler (keda.sh); Traefik/Jaeger/OTel/external-dns charts (artifacthub).
Full URLs in the session research streams.
