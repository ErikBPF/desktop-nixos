# Implementation plan — declarative cluster/registry setup

**Date:** 2026-06-22
**Status:** In progress — partially applied (mixed `[x]`/`[ ]`/`[~]` below); open decisions marked `TODO(erik)`.
**Type:** Spec / work-items (executable breakdown). Rationale lives in the RFCs:
- [`2026-06-22-harbor-declarative.md`](../implemented/2026-06-22-harbor-declarative.md) — Harbor → static stack
- [`harbor-discovery-registry.md`](../reference/harbor-discovery-registry.md) — the deployed (imperative) baseline
- [`2026-06-22-harbor-pullthrough-mirror.md`](../implemented/2026-06-22-harbor-pullthrough-mirror.md) — mirror design

**Scope:** move every imperative/stateful edge of the Harbor + k3s-mirror setup
into declarative source. Ordered by dependency; each item has a verify gate.
Decisions still open are marked `TODO(erik)` — don't silently resolve them.

Legend: `[ ]` todo · `[x]` done this session · `[~]` partial.

---

## Already declarative (done — baseline)

- [x] **k3s mirror wiring** — `registries.yaml` + `networking.hosts` pin moved
  out of the shared `_k3s-node.nix` into kepler's `mkGuest`
  (`modules/hosts/kepler/k3s-cluster.nix`), domain via `harbor.homelab.${domain}`.
  Reconciles on `switch`. *(/simplify)*
- [x] **etcd-expose + ingress-nginx removal** — in `_k3s-node.nix` /
  `k3s-cluster.nix` (`575969d`). Applied via the bounce.
- [x] **Harbor secrets** — `HARBOR_ADMIN_PASSWORD`/`HARBOR_DB_PASSWORD` in
  servarr `.env.sops` (sops), pushed.

The remaining imperative edges are the targets below.

---

## A. Harbor → declarative — DONE (oneshot, not static stack) `[x]`

**Outcome:** the static-stack path (A1–A4 below) was attempted and abandoned —
capturing `prepare`'s output to git flips config ownership and breaks
`harbor-log`/registry (see [`2026-06-22-harbor-declarative.md`](../implemented/2026-06-22-harbor-declarative.md)
§Outcome). Implemented instead as a **NixOS oneshot**
(`modules/hosts/discovery/harbor.nix`): pinned installer (`fetchurl`),
`harbor.yml` rendered from `.env`, `prepare` + `compose up` run by a root
`systemd.services.harbor` oneshot (stamp-guarded so it only re-prepares on
change; reconciles on switch). `harbor-setup.sh` is retained (the service's
ExecStart), not killed. Verified live: service active, harbor-core healthy,
edge 200. The A1–A4 static breakdown below is kept for the record only.

### A1 — capture prepare output  `[ ]`
- [ ] Run `prepare` once against the rendered `harbor.yml` (host or local).
- [ ] Commit generated `docker-compose.yml` → servarr as
  `machines/discovery/harbor.yml`, with the `redis|registry|registryctl|nginx →
  harbor-*` renames **baked in** (no runtime `sed`).
- [ ] Commit the static `common/config/*` tree under
  `machines/discovery/config/harbor/common/`.
- [ ] Confirm image tags pinned (`goharbor/*:v2.14.4`).
- **Verify:** `docker compose -f harbor.yml config` parses; container_names are
  all `harbor-*`.

### A2 — externalize secrets  `[ ]`  ← the hard part
- [ ] Enumerate every secret `prepare` baked into `common/config/*/env`
  (`db/env` pw, `core/env` `SECRET_KEY`+`CSRF_KEY`, `jobservice/env`,
  registry/registryctl HTTP secret). Drive each from `.env.sops` via compose
  `env_file`/`environment`.
- [ ] `TODO(erik)` **registry token-service TLS key** (prepare mints it
  per-install): decide commit-as-sops **vs.** a `mint-if-missing` ExecStartPre.
  (Recommend mint-if-missing — avoids committing a keypair; one tiny idempotent
  edge.)
- **Verify:** `grep -rIE '(password|secret|key).*[A-Za-z0-9]{16,}'
  config/harbor/common` returns nothing (no plaintext secrets committed);
  `git show :machines/discovery/harbor.yml` has no secrets.

### A3 — wire into homelab.compose  `[ ]`
- [ ] Add `"harbor"` to `modules/hosts/discovery/compose.nix` `stacks`.
- [ ] Delete `machines/discovery/scripts/harbor-setup.sh`.
- [ ] Drop the `.harbor-installer` + rendered-`harbor.yml` gitignore lines
  (servarr `.gitignore`) and the `.harbor-installer` rsync exclude (desktop-nixos
  `justfile`) — no longer needed.
- **Verify:** `just dry discovery`; after switch, the `…-compose-harbor` unit is
  active and Harbor comes up identically (UI 200 via SWAG, login works).

### A4 — version-bump workflow  `[ ]`
- [ ] Add `just harbor-regen <version>` (servarr or desktop-nixos): re-run
  `prepare` for the new version into a temp dir, diff against the committed
  compose/config, print the diff to review. Bump = a reviewed git change.
- **Verify:** running it on the current version produces an empty diff.

---

## B. harbor-proxycache → declarative  `[x]` (2026-06-28, deploy pending)

The Docker Hub proxy-cache project is created by an imperative API script.
- [x] **Folded into the harbor oneshot.** `harbor-proxycache.sh` (idempotent,
  public project) now runs as a non-fatal `ExecStartPost` on
  `systemd.services.harbor` (`modules/hosts/discovery/harbor.nix`) — `After` the
  compose-up, best-effort (`-` prefix) so a transient Harbor-not-ready never flaps
  the unit. Decided: **public** project (= harbor-pullthrough P2). Dry-built;
  deploy pending a stable discovery window.
- **Verify (on deploy):** fresh `nixos-rebuild switch` on an empty Harbor yields
  the `dockerhub` proxy project with no manual step.

---

## C. Self-cleaning autoDeployCharts removal  `[ ]`

Gotcha hit this session: removing a chart from `services.k3s.autoDeployCharts`
leaves the **stale manifest file** in `/var/lib/rancher/k3s/server/manifests/`
(NixOS doesn't delete stateful files it no longer manages), so k3s keeps
redeploying it — ingress-nginx had to be removed manually on all 3 servers + the
HelmChart CR deleted by hand.
- [ ] Make removal self-cleaning so the next chart removal needs no manual `rm`.
  `TODO(erik)` approach:
  - **Narrow:** a `systemd.tmpfiles.rules` `r` (remove) entry per retired chart
    manifest (explicit, simple, but a per-removal special case), **or**
  - **General (preferred):** an activation/oneshot that reconciles the manifests
    dir to exactly the declared `autoDeployCharts` set (removes extras) — fixes
    the whole class, not one file.
- **Verify:** add then remove a throwaway chart from `autoDeployCharts`, switch
  → the manifest file and its HelmChart CR are gone with no manual action.

---

## D. Related operational debt (not declarative, surfaced this session)  `[ ]`

Track here so it isn't lost; fix alongside the above.
- [ ] **Deploy-recipe sudo** — `just switch-kepler` exited 4 on remote-sudo
  elevation (new nixos-rebuild 26.11 wants `--ask-elevate-password` or
  passwordless sudo). Switch applied anyway, but the recipe should report clean.
  Fix the `deploy` recipe (`justfile`).
- [x] **Status-doc correction** (2026-06-27) — `kepler-k3s-platform-status.md`
  "host-only vs guest changes" gotcha corrected: `switch` restarts **all** guests
  at once (full-cluster bounce), not a graceful rolling window.
- [ ] **etcd observability follow-on** — etcd metrics now flow on `:2381`. Add
  the `alloy-metrics` etcd scrape (gitops) + an etcd Grafana dashboard (servarr).

---

## Sequencing

```
A1 → A2 → A3 → A4         (Harbor static stack; A3 deletes the installer)
        └─→ B             (proxy-cache init; after Harbor rides homelab.compose)
C, D  — independent, any time
```

A3 is the cutover (deletes `harbor-setup.sh`); do it only after A1+A2 verify, and
keep the installer path until the static stack is proven to come up clean.

## Risk / rollback

- A2 is the risk concentration (secret wiring). Keep `harbor-setup.sh` in git
  until A3's verify passes; revert = re-add `"harbor"`... no — revert = drop the
  static stack + restore the script (one git revert).
- No cluster bounce in any of A/B (discovery-only). C touches k3s guest config →
  fold into a scheduled bounce window.
```
