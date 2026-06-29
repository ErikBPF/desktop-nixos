# kepler k3s platform — implementation status

As-built snapshot of the kepler Kubernetes platform: the k3s cluster (NixOS
microvms, this repo) plus the GitOps workloads (`homelab-gitops` sister repo,
servarr-style — **not** Nix-deployed). Pairs with the two design docs:
[`proposals/2026-06-19-kepler-k3s-microvm-cluster.md`](../proposals/2026-06-19-kepler-k3s-microvm-cluster.md)
(the cluster) and
[`proposals/2026-06-20-cluster-homelab-gitops.md`](../proposals/2026-06-20-cluster-homelab-gitops.md)
(the workloads). Recipes in `justfile` remain the operational source of truth;
this doc explains the shape and tracks what's left.

Last updated: 2026-06-21.

## Topology

```
                    home LAN (192.168.10.0/24)
   .245 ─ apiserver VIP ┐                  ┌─ .250 ─ ingress endpoint
                        │   kepler host    │
                        │  L4 LB (nginx)   │
        ┌───────────────┴──────────────────┴───────────────┐
        │  br-k3s private subnet 10.250.0.0/24 (microvms)   │
        │   cp-1 .11   cp-2 .12   cp-3 .13   (HA etcd)       │
        │   worker-1 .21   worker-2 .22                     │
        └───────────────────────────────────────────────────┘
                        │ push telemetry (tailnet)
                        ▼
        discovery: Loki :3100 · Prometheus :9090 (remote-write)
```

- **Cluster**: k3s on NixOS microvms (cloud-hypervisor), HA embedded etcd.
  3 control-plane (2 vCPU / 4 GB) + 2 workers. Defined entirely in
  `modules/hosts/kepler/k3s-cluster.nix` (dendritic). Scale workers by bumping
  `workerCount` + switch.
- **kepler L4 LB** (host nginx stream): `.245:6443` → apiserver; `.250:443` →
  worker NodePort `30444` (Traefik, post-cutover). Host-only config — reloading
  it does **not** bounce the guests.
- **Guests boot from their closure** (`/nix/store` shared ro via virtiofs;
  `root.img` is writable state only). A guest **config** change swaps the
  closure and is applied by **restarting `microvm@<name>`** — i.e. a rolling
  node bounce. Host-only changes (the LB) reload in place.
- **Telemetry is push-based** to discovery over the tailnet (ACL-gated). Pods
  can't resolve MagicDNS, so agents target discovery's raw tailnet IP.

## Implemented

### Cluster (this repo — `k3s-cluster.nix`)

- HA 3-CP + 2-worker microvm cluster, staggered boot ordering
  (`microvm@` After-chains) so etcd forms cleanly.
- `br_netfilter` + bridge-nf sysctls; networkd kept off the CNI interfaces
  (cni0/flannel/veth/cali/vxlan unmanaged) so pod networking survives the
  static-IP setup.
- NAT egress for the private subnet via kepler; guest firewalls off (isolated
  subnet, only `.245`/`.250` exposed via the LB).
- Per-CP embedded-etcd **snapshots** to a host-backed `/bulk` share (virtiofs).
- `autoDeployCharts` declared on **all** servers (not just cp-1) so the
  helm-install job resolves the static chart whichever apiserver it lands on.
- Single-replica **Alloy** (`alloy-metrics`) in-cluster: KSM + per-node kubelet
  cAdvisor + **Traefik** (`traefik-metrics` svc :9100) → discovery Prometheus.
  Separate Alloy DaemonSet ships pod logs → discovery Loki, label cardinality
  trimmed (drops `pod`, keeps namespace/app/container). **etcd metrics are NOT
  scraped** — k3s embedded etcd needs `--etcd-expose-metrics` (guest flag →
  rolling CP bounce); deferred to the next bounce window.
- LB ingress upstream cut over from ingress-nginx (`30443`) to **Traefik
  (`30444`)** — host nginx reload, no guest bounce.

### GitOps workloads (`homelab-gitops` — servarr-style, not Nix)

Argo CD app-of-apps, sync-waves, thin Helm wrapper charts. **14 applications
Synced + Healthy:**

| App | Role |
|-----|------|
| `argocd` | GitOps controller (app-of-apps root) |
| `vault` | In-cluster Vault (standalone, file storage on local-path, HTTP) + auto-unseal poller Deployment |
| `external-secrets` | ESO → Vault via AppRole (`ClusterSecretStore vault-incluster`) |
| `csi-driver-nfs` | `nfs-fast` + `nfs-slow` storage classes |
| `traefik` | **Default** IngressClass (post-cutover), NodePort 30444/30081 |
| `harbor` | Registry (admin pw via ESO/existingSecret, Trivy off for lab weight) |
| `keda` | Cron `ScaledObject` scale-to-zero |
| `jaeger` + `otel-collector` | Tracing backend + collector |
| `trace-demo` | telemetrygen trace producer |
| `kube-state-metrics` | Cluster-object metrics |
| `alloy-metrics` | KSM + cAdvisor + Traefik scrape → discovery Prometheus |
| `demo` | Flagship: podinfo + Vault env + NFS PVC + KEDA + restricted PSA + NetworkPolicy |
| `root` | App-of-apps parent |

**Validated end-to-end:**

- Vault auto-unseal (kill `vault-0` → re-unsealed ~30 s, ESO reconnects).
- Demo: Vault-sourced env, NFS PVC Bound, ingress 200, KEDA HPA active,
  restricted PodSecurity, NetworkPolicy (default-deny + DNS + ingress).
- **Traefik cutover**: argocd / harbor / demo all 200 through the `.250` LB,
  served by Traefik. Caught + fixed a 502 — demo's NetworkPolicy admitted only
  `ingress-nginx`; widened `allow-ingress` to `{traefik, ingress-nginx}`.

### Supporting (discovery / servarr)

- Prometheus `--storage.tsdb.retention.size=50GB` backstop; Loki `:3100` +
  Prometheus `:9090` (remote-write-receiver) published, tailnet-ACL gated.
- `just kubeconfig-lan` recipe (LAN VIP `.245`).

## Next steps

### Done (2026-06-21)

- **k8s Grafana dashboards** on discovery — `k3s Cluster Health` (KSM+cAdvisor)
  + `Traefik Ingress` (after enabling traefik metrics, no bounce) + `Node
  Exporter Full` (1860). All provisioned + verified. etcd dashboard deferred
  (no metrics until the `--etcd-expose-metrics` bounce).
- **Grafana hardening env** — cookie_secure / cookie_samesite=strict /
  disable_gravatar / allow_sign_up=false live. `secret_key` gated on
  `GRAFANA_SECRET_KEY` landing in `.env.sops`. (`hide_version` is not a real
  Grafana setting — dropped.)
- **ntfy alerting** — disk-fill `predict_linear` rule + ntfy webhook contact
  point + root policy; Prometheus datasource uid pinned to `prometheus`.

### Deferred — needs a deliberate node bounce (schedule, ideally with orion up)

- **Harbor pull-through mirror** — point k3s nodes at Harbor via
  `registries.yaml`. This is declarative guest config → swaps the guest closure
  → **rolling microvm restart** across the CPs (etcd quorum). Small build, but
  the staggered restart is the real cost; offloading the build to orion makes
  the deploy fast. Not orion-*blocked*, just safer to schedule.
- **Remove idle ingress-nginx** — currently idle on `30443`, kept as a
  one-flip rollback for the Traefik cutover. Removing it from `autoDeployCharts`
  is a guest-config change → same rolling-bounce window. Do it together with the
  mirror change to spend one bounce, not two.
- **etcd metrics** — add `--etcd-expose-metrics` to the k3s server flags
  (`k3s-cluster.nix`) so etcd exposes `/metrics`, then scrape it from
  `alloy-metrics` and build the etcd dashboard. Guest-config change → rolling CP
  bounce; fold into the same window.

### Needs user action

- **Renovate** — enroll `homelab-gitops` (`.env` token).
- **Branch protection** on `homelab-gitops`.
- **etcd restore drill** — exercise a snapshot restore (destructive; explicit
  confirmation).
- **k8up backup target** — pick where cluster backups land.

## Gotchas (learned the hard way)

- **Never deploy the cluster while orion is down via the orion-offload path.**
  The remove-ingress-nginx attempt failed mid-flight *after* stopping the CP
  microvms (build offloaded to a dead orion) → API outage. Recovery was a manual
  staggered CP restart. Build locally (`--option builders ""`) or wait for orion.
- **Host-only vs guest changes**: the LB (host nginx) reloads with no bounce;
  anything in the guest NixOS config (registries, charts, node flags) restarts
  the microvms. **A `switch` restarts *all* changed guests at once — a
  full-cluster bounce, not a graceful one-at-a-time roll** (confirmed
  2026-06-27; the closure is shared, so a fleet-wide change bounces every CP +
  worker together, risking etcd quorum). Plan guest changes for a maintenance
  window and stagger the CP restarts manually if availability matters.
- **ESO CRDs are `v1`** (not `v1beta1`); spell out the server-default fields
  (conversion/decoding/metadata/nullByte/deletion policies) or the
  ExternalSecret sits perpetually OutOfSync.
- **Multi-apiserver chart 404**: the helm-install job hits an arbitrary
  apiserver — the static chart must exist on all servers (`autoDeployCharts` on
  every server role).
- **Argo repo SSH secret**: create with
  `kubectl create secret generic --from-file=sshPrivateKey=<keyfile>` — heredoc/
  sed indentation corrupts the key.
- **Pods can't resolve tailnet MagicDNS** → telemetry agents use discovery's raw
  tailnet IP, not the hostname.
