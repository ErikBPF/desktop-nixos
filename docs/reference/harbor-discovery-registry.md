# Harbor on discovery — registry + Docker Hub pull-through

**Date:** 2026-06-22 (deployed; push fixed 2026-06-29)
**Status:** Deployed + live. Proxy-cache **and** push both work.
**Decision:** Harbor runs as a Docker stack on **discovery** (the 24/7 infra
host), not in-cluster. Moving it off the k3s cluster kills the self-hosting
bootstrapping trap (a cluster mirror can't depend on a registry living inside
the cluster it serves) and consolidates registries on the host that already runs
every other Docker stack. The in-cluster Harbor (gitops Argo app) is **removed**
once this is verified up.

Artifacts live in the `servarr` repo under `machines/discovery/`:
- `config/harbor/harbor.yml.tmpl` — Harbor config template (rendered from `.env`).
- `scripts/harbor-setup.sh` — fetch pinned installer, render, install (Trivy off).
- `scripts/harbor-proxycache.sh` — create the `dockerhub` proxy-cache project (API).
- `config/swag/nginx/proxy-confs/harbor.subdomain.conf` — TLS edge.
- `.env.example` — `HARBOR_ADMIN_PASSWORD`, `HARBOR_DB_PASSWORD`, optional
  `DOCKERHUB_USER`/`DOCKERHUB_TOKEN`.

The k3s mirror wiring is in **desktop-nixos** (`_k3s-node.nix`, a guest bounce) —
see step 6. This supersedes the in-cluster bits of
[`proposals/2026-06-22-harbor-pullthrough-mirror.md`](../proposals/2026-06-22-harbor-pullthrough-mirror.md).

## Host facts

- Hostname: `harbor.homelab.pastelariadev.com` (distinct from the old in-cluster
  `harbor.k8s.pastelariadev.com`, so both can coexist during migration).
- TLS: covered by SWAG's existing `*.homelab.pastelariadev.com` wildcard
  (cloudflare DNS-01) — no new cert.
- Storage: `/home/erik/vault/harbor` (1.8 T free).
- RAM: discovery is busy (~15 G available, 53 containers). Harbor without Trivy
  is ~2–3 G — fits, but watch it. Trivy stays off.

## Deploy sequence

> Each step verified before the next. Steps 1–5 are no-cluster-impact; step 6 is
> the guest bounce (fold into the etcd/nginx window, commit `575969d`).

1. **Secrets** — generate + add to `.env.sops`, then push:
   ```
   # ~/Documents/erik/servarr/machines
   just decrypt-env discovery            # or edit-env
   #   HARBOR_ADMIN_PASSWORD=$(openssl rand -hex 24)
   #   HARBOR_DB_PASSWORD=$(openssl rand -hex 24)
   just encrypt-env discovery && just push-env discovery
   ```
2. **DNS** — add `harbor.homelab.pastelariadev.com → 192.168.10.210` (AdGuard
   rewrite / homelab-iac), like the other discovery services.
3. **Deliver** — commit + push the servarr changes (template, scripts, SWAG
   conf), then `just pull-servarr discovery`. Reload SWAG so the new proxy-conf
   loads: `docker exec swag nginx -s reload` (or recreate swag).
4. **Install Harbor** on the host:
   ```
   ssh -p 2222 erik@discovery 'bash /home/erik/servarr/machines/discovery/scripts/harbor-setup.sh'
   ```
   Verify: `https://harbor.homelab.pastelariadev.com` loads; `docker login
   harbor.homelab.pastelariadev.com -u admin`.
5. **Proxy-cache project**:
   ```
   ssh -p 2222 erik@discovery 'bash /home/erik/servarr/machines/discovery/scripts/harbor-proxycache.sh'
   ```
   Verify pull-through:
   `docker pull harbor.homelab.pastelariadev.com/dockerhub/library/busybox`
   → succeeds, and the `dockerhub` project shows the cached repo.
6. **Point k3s at the mirror** (desktop-nixos, guest bounce). Add to
   `_k3s-node.nix` a `/etc/rancher/k3s/registries.yaml` via `environment.etc`:
   ```yaml
   mirrors:
     docker.io:
       endpoint:
         - "https://harbor.homelab.pastelariadev.com/v2/dockerhub"  # proxy first
         - "https://registry-1.docker.io"                            # fallback
   ```
   **Verify before the bounce**: a cluster node can resolve + reach
   `harbor.homelab.pastelariadev.com:443` (node → kepler NAT → LAN .210). Then
   dry-build + rolling guest restart (same window as etcd-expose + nginx removal;
   local build while orion is down). Verify `crictl pull` on a node routes
   through Harbor; kill Harbor briefly → pulls still succeed via the fallback.
7. **Remove the in-cluster Harbor** — only after step 5 is healthy. Delete the
   Harbor Argo app + `platform/harbor/` from homelab-gitops (Argo prunes it).
   Staged on a branch / held for your push.

## Pushing images (as-built, 2026-06-29)

Only the proxy-cache path was exercised at install; the **first real `docker
push`** (the `kindle-dash` OSS image, P4/D8) surfaced an ingress bug. The SWAG
vhost set `X-Forwarded-Proto https` on top of the included `proxy.conf` (which
already sets it to `$scheme`); nginx emitted the header twice, Harbor's core
joined it to `https, https` and built a malformed blob-upload `Location`
(`https, https://…`) — push failed, pulls were fine. Fix: drop the redundant
directive in `servarr` `config/swag/nginx/proxy-confs/harbor.subdomain.conf`
(committed there with a defensive comment).

- **Public `library` project** holds OSS mirrors (anon pull, authed push) — e.g.
  `harbor.homelab.pastelariadev.com/library/kindle-dash:<tag>`.
- **Push auth:** a **scoped robot `robot$library+mirror`** (project `library`,
  `repository` push+pull, no expiry) — created 2026-06-29 via the admin API
  (admin pw from OpenBao `secret/home/harbor` → `/run/vault-agent/harbor.env`,
  `sudo`-read). Least-priv: it can push only `library`, not the whole registry.
- **Mirror tool:** `servarr` `machines/discovery/scripts/harbor-mirror.sh` reads
  `HARBOR_ROBOT_USER`/`HARBOR_ROBOT_SECRET` from env, copies GHCR→Harbor `library`
  (skopeo if present, else docker pull/tag/push), and **strips a leading `v`** —
  pass `0.1.0` or `v0.1.0`, it mirrors the v-less tag CI publishes
  (`docker/metadata-action` drops the `v`). Run on discovery (reaches GHCR + the
  LAN-only Harbor); public GH runners can't, so CI publishes GHCR only.

## Follow-ups

- **Seal the robot secret.** It currently sits in `/home/erik/harbor-mirror-robot.env`
  (mode 600, owned `erik`) on discovery — fine to run mirrors from, but not the
  SSOT. Move it into OpenBao `secret/home/harbor`
  (`HARBOR_ROBOT_USER`/`HARBOR_ROBOT_SECRET`) and have vault-agent render it
  beside the admin/db passwords (D5). Blocked today: the `vault_root_token` in
  desktop-nixos sops is **stale** (rotated 2026-06-29 to an orphan root-policy
  token, sops copy not updated) — reseal it, or use the current root token to
  `bao kv patch`, then drop the plaintext file.
- **The X-Forwarded-Proto fix is registry-wide**, not kindle-dash-specific: it
  unblocks *every* future `docker push` to Harbor. Keep the defensive comment in
  `harbor.subdomain.conf` so the duplicate header isn't reintroduced.

## Rollback

- Harbor stack: `cd .harbor-installer/harbor && docker compose down` (data
  persists in `/home/erik/vault/harbor`).
- Mirror: the upstream fallback endpoint means a broken/missing Harbor degrades
  to direct Docker Hub pulls; full revert = drop `registries.yaml` + bounce.
- In-cluster Harbor removal is the last + only hard-to-reverse step — do it only
  once discovery Harbor is proven.
