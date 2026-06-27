# Harbor pull-through mirror for the kepler k3s cluster

**Date:** 2026-06-22
**Status:** Proposal (scoped, not applied) — `TODO(erik)` decisions marked
**Scope:** point k3s nodes at Harbor as a Docker Hub pull-through cache, to cut
external pulls + dodge Docker Hub rate limits (prod-mimic). Pairs with
[`kepler-k3s-platform-status.md`](../reference/kepler-k3s-platform-status.md).

## TL;DR

Not a one-line `registries.yaml` change. Two repos + a guest bounce, and a
**self-hosting bootstrapping trap** to defuse first. Sequence: create the Harbor
proxy project (cluster-up, gitops/API), then add `registries.yaml` with an
**upstream fallback** and bounce the guests.

## Current state (verified 2026-06-22)

- Harbor deployed (chart 1.19.1), `externalURL https://harbor.k8s.pastelariadev.com`,
  ingress `className: traefik` + TLS — reachable through the `.250` LB.
- **No proxy-cache project exists.** The chart description says "Docker Hub
  proxy-cache" but nothing creates the registry endpoint or project. The Harbor
  helm chart does not provision projects declaratively.
- **No `registries.yaml`** on any node. NixOS `services.k3s` has no `registries`
  option (confirmed) — the file must be written via `environment.etc` in each
  guest's config → a guest-config change → **rolling microvm bounce**.

## The bootstrapping trap (defuse FIRST)

Harbor runs **inside** the cluster it would mirror for. If nodes use Harbor as
the sole `docker.io` endpoint and Harbor is down (cold start, its own rollout,
an NFS hiccup on `nfs-fast`), every workload image pull fails — including
Harbor's own images → deadlock.

Mitigations (apply both):
1. **List the upstream as a fallback endpoint.** containerd tries mirror
   endpoints in order and falls through on failure:
   ```yaml
   mirrors:
     docker.io:
       endpoint:
         - "https://harbor.k8s.pastelariadev.com/v2/dockerhub"   # proxy first
         - "https://registry-1.docker.io"                         # fallback
   ```
2. k3s core images (pause, coredns, metrics-server, …) are already baked into
   the node closure (`airgap-images-amd64`), so a Harbor outage only affects
   *workload* pulls, never k3s bringup. Good — keep it that way.

## Prerequisites (the real work, all cluster-up / no bounce)

### P1 — Harbor proxy-cache project + registry endpoint

Create via the Harbor API (idempotent Job in gitops, or one-time manual):
- `POST /api/v2.0/registries` — a registry of type `docker-hub`, URL
  `https://hub.docker.com`. (Optionally add Docker Hub creds to lift the
  anonymous rate limit — `TODO(erik)`: worth a Hub account token?)
- `POST /api/v2.0/projects` — project `dockerhub`, `registry_id` = the above,
  `metadata.public = "true"` (see P2).

**`TODO(erik)`** delivery: a `Job`/`CronJob` in `platform/harbor/templates/`
that curls the Harbor API using the admin secret (idempotent: check-then-create),
vs. a documented manual one-time setup. Recommend the Job — declarative, survives
a Harbor reinstall.

### P2 — Auth for node pulls

Two options:
- **Public proxy project (recommended for lab):** `metadata.public=true` →
  anonymous pull → **no credentials in `registries.yaml`**. Simplest; avoids
  putting a robot token in guest Nix config (which would need sops-on-guest —
  currently deferred, see status doc). Pull-through still caches.
- **Robot account:** `robot$dockerhub-puller` with pull scope → token in
  `registries.yaml` `configs.<host>.auth`. More prod-like, but the token is a
  guest secret → needs the deferred sops-on-guest host key first. Defer.

`TODO(erik)`: confirm public-project pull-through is acceptable (it only exposes
*cached public Docker Hub images* to anyone already on the cluster network).

### P3 — Node → Harbor DNS/routing

Nodes (containerd) must resolve `harbor.k8s.pastelariadev.com` and route to it.
Path is a hairpin: node (10.250.0.x) → NAT via kepler → `.250` LB → Traefik →
Harbor pod. **`TODO(erik)`/verify at deploy:** does the guest resolver return
`.250` for that name? If not, pin it — either a `networking.hosts` entry
(`192.168.10.250 harbor.k8s.pastelariadev.com`) in the guest config, or point
`registries.yaml` straight at the LB. TLS: Harbor's cert must be valid for the
name the node dials (keep the hostname, not the IP, so the LE/Traefik cert
matches; otherwise `tls.insecure_skip_verify` — avoid).

## Changes (once prereqs are met)

| Repo | Change | Bounce? |
|------|--------|---------|
| homelab-gitops | `platform/harbor/templates/` Job to create registry + `dockerhub` project (P1/P2) | no (Argo) |
| desktop-nixos | `_k3s-node.nix` (or kepler guest): `environment.etc."rancher/k3s/registries.yaml".text = …` with proxy + upstream fallback | **yes — rolling guest bounce** |

`registries.yaml` belongs in the **shared** `_k3s-node.nix` (all nodes) so every
node uses the mirror, mirroring how `extraFlags`/`images` are defined there.

## Deploy sequence (fold into the etcd + ingress-nginx bounce)

1. Land P1/P2 in gitops → Argo syncs → **verify the proxy works while the
   cluster is still on the old config**: from a node or a debug pod,
   `crictl pull harbor.k8s.pastelariadev.com/dockerhub/library/busybox` (or curl
   the `/v2/` proxy) → confirm Harbor caches it (project repo populates).
2. Only after P1 verifies: add `registries.yaml` to the guest config, dry-build,
   and bounce the guests **in the same window** as `--etcd-expose-metrics` +
   ingress-nginx removal (commit `575969d`) — one staggered restart, not three.
3. Build locally (`builders=`) while orion is down; staggered CP restart with
   etcd-quorum checks between each, workers after.

## Verification

- `crictl pull` of a `docker.io/library/*` image on a node goes via Harbor
  (Harbor `dockerhub` project shows the cached repo).
- Kill Harbor briefly → pulls still succeed via the upstream fallback endpoint
  (proves the trap is defused).
- All pods stay Running through the bounce; no `ImagePullBackOff`.

## Rollback

Remove `registries.yaml` from the guest config → bounce. Or, less invasively,
the upstream fallback endpoint means a broken Harbor proxy degrades to direct
Docker Hub pulls without intervention.

## Effort / risk

- P1+P2 (gitops Job): **M** — Harbor API scripting, idempotency.
- registries.yaml + bounce: **S** code, **the bounce is the cost** (shared with
  etcd/nginx window).
- Risk: **medium** — mitigated by the upstream fallback + verifying P1 before the
  bounce. Without the fallback it's **high** (self-hosting deadlock).
