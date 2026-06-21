# `homelab-gitops` — a production-mimicking platform layer for the kepler k3s cluster

**Date:** 2026-06-20
**Status:** Proposal (skeleton — judgment marked `TODO(erik)`)
**Owner:** erik
**Scope:** a NEW sister repo (servarr-style: symlink under `references/repos/`,
`just` recipes) that adds a production-grade platform layer to the kepler k3s
cluster. **Not NixOS-deployed** — applied to the cluster like servarr's docker
stacks. Telemetry hardening of the existing stack is separate —
[`2026-06-20-telemetry-hardening.md`](2026-06-20-telemetry-hardening.md).

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
| Secrets | **ESO → Vault@discovery** | `external-secrets` v2.6.0 | AppRole auth (see §5) |
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

## 5. Secrets — External Secrets Operator → Vault on discovery

Prod-mimic secrets: a **Vault on discovery** (new servarr docker stack), ESO in
the cluster syncs from it.

- **Vault deploy (discovery, servarr-style):** `hashicorp/vault:1.21`, **integrated
  Raft** storage (not dev mode, not `file`), low unseal threshold, unseal key in
  **sops-nix on discovery**, an entrypoint/systemd unit auto-runs
  `vault operator unseal` on boot (real seal lifecycle, no KMS). Compose follows
  servarr (`cap_add: IPC_LOCK`, Raft data volume, TLS cert mounted). Publish
  `8200`.
- **Auth: AppRole** (not Kubernetes auth). AppRole = ESO-calls-Vault-only,
  matching the egress direction (pod → kepler NAT → discovery:8200). Kubernetes
  auth would force Vault to call *back* into kepler:6443 (reverse trust, long-lived
  reviewer JWT) — not worth it for one Vault/one cluster.
- **ESO:** chart `external-secrets` v2.6.0; a `ClusterSecretStore` with inline
  `role_id` (non-secret) + `secret_id` from a k8s Secret; `caProvider` → a
  `vault-ca` ConfigMap. **Keep Vault TLS on** even over the tailnet (endpoint
  auth + prod habit; no `VAULT_SKIP_VERIFY`); cert SANs `100.76.140.121` +
  `discovery`.
- **Bootstrap seed (chicken-and-egg):** ESO needs exactly one secret — the
  AppRole `secret_id`. Encrypt it in **sops-nix on kepler** and materialize the
  `vault-approle` Secret via `/var/lib/rancher/k3s/server/manifests/` (encrypted
  at rest, survives rebuilds, no new tooling). `role_id` committed inline.
- **Network:** ACL grant `kepler → discovery tcp:8200` in **homelab-iac** (mirror
  the Loki/Prometheus grant); publish Vault `8200` on discovery (servarr).

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
│   ├── external-secrets/ (-3)    # ESO + ClusterSecretStore→Vault@discovery
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
   needs: ESO secret_id seed ──────────▶ desktop-nixos sops-nix (k3s manifests)
   needs: registries.yaml Harbor mirror ▶ desktop-nixos _k3s-node.nix
homelab-iac: ACL grant kepler→discovery tcp:8200 (Vault); + external-dns egress
servarr/discovery: NEW vault stack (Raft, sops-unseal); Prometheus gains cluster
                   metrics via remote_write (telemetry RFC)
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
- Vault unseal automation shape (sops + systemd unit on discovery) — acceptable,
  or auto-unseal via a transit Vault (over-engineering for a lab)?
- Jaeger storage (badger vs ES); traces in Jaeger UI vs also Grafana/Tempo?
- Repo name + does it own future multi-cluster (ApplicationSet generators)?

## 15. Sources

argo-cd chart 9.6.0 + cluster-bootstrapping (argo-cd.readthedocs.io);
external-secrets v2.6.0 + Vault provider (external-secrets.io); Vault Raft +
AppRole (developer.hashicorp.com/vault); csi-driver-nfs 4.12.0 (kubernetes-csi);
Harbor prereqs 2 CPU/4 GB/40 GB (goharbor.io/docs/install-config); KEDA 2.20 +
prometheus scaler (keda.sh); Traefik/Jaeger/OTel/external-dns charts (artifacthub).
Full URLs in the session research streams.
