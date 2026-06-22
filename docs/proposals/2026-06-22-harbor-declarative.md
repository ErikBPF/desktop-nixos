# RFC: make the discovery Harbor fully declarative

**Date:** 2026-06-22
**Status:** Implemented — **oneshot variant**, not the static stack this RFC
originally recommended. See Outcome.

## Outcome (2026-06-22)

The static-stack path (§Plan below) was attempted and **abandoned**: capturing
Harbor's `prepare` output into git and deploying it flips file ownership to the
deploy user, and several components reject that — `harbor-log`'s rsyslog refuses
a config it doesn't own ("no active actions"), and the bulk config-capture +
world-read perms fought the deploy at every step. Root cause: `prepare` lays
config down in-place with component-specific ownership; vendoring it to git +
git/rsync checkout breaks that.

**Implemented instead: the "rejected alternative" oneshot** (`modules/hosts/
discovery/harbor.nix`). It keeps `prepare` as the reproducible build step and
makes it declarative — installer Nix-pinned (`fetchurl`), `harbor.yml` rendered
from the host `.env`, `prepare` + `compose up` run by a root `systemd.services.
harbor` oneshot that stamp-guards re-prepare and reconciles on every switch. No
committed derived config, no secret-externalization, no ownership flips. Verified
live: `harbor.service` active, harbor-core healthy, edge 200, 9 `harbor-*`
containers. The static plan below is retained for the record only.

---

**Original status:** Proposal — judgment calls marked `TODO(erik)` (RFC content is
human-owned; this is structure + analysis only)
**Supersedes the imperative bits of:**
[`harbor-discovery-registry.md`](../harbor-discovery-registry.md)

## Goal

Harbor on discovery should be reproducible from git with **no imperative
install step** — at the same declarative level as every other discovery stack.

## Why it isn't today

`scripts/harbor-setup.sh` is imperative at deploy time:
1. `curl`s the Harbor online-installer tarball from GitHub at runtime.
2. Runs `prepare` (a container) to **generate** `docker-compose.yml` +
   `common/config/*` on the host from `harbor.yml`.
3. `sed`-patches generated container names.
4. `docker compose up`.

The generated compose + config are **gitignored** — the running state is not
derivable from source. `harbor-proxycache.sh` then mutates Harbor over its API.

## The key realization — the fleet is already declarative here

`modules/server/orchestration.nix` defines `homelab.compose`:
`homelab.compose.stacks = [ "infra" "networking" "monitoring" … ]`. From that
list NixOS generates:
- a `servarr-pull` user service — clones/FF-pulls the servarr repo, decrypts
  `.env.sops` → `.env` (sops), ensures `homelab-net`;
- one ordered `…-compose-<stack>` systemd unit per stack —
  `docker compose -f <stack>.yml up -d`.

This is GitOps-for-compose: the **servarr repo is the desired state**, NixOS
reconciles it on boot/switch. Every other discovery service already rides it.
**Harbor just needs to become a static `harbor.yml` stack in this list.** No
bespoke `systemd.services.harbor` — that would diverge from the established
mechanism (rejected alternative, see §Alternatives).

## Plan — turn Harbor into a static committed stack

The obstacle is `prepare`. But `prepare`'s output is **deterministic** from
`harbor.yml`, and the split is clean:
- `docker-compose.yml` — **no secrets** (image refs, volumes, networks,
  container_names). Safe to commit.
- `common/config/*` — mostly static (nginx.conf, registry config.yml), plus a
  handful of **secret-bearing env files** (`db/env` password, `core/env`
  secretkey, etc.).

### Phase 1 — capture (one-time, at authoring time, not deploy)
1. Run `prepare` once (locally or on host) against the rendered `harbor.yml`.
2. Commit the generated `docker-compose.yml` to servarr as `harbor.yml` (the
   stack file), with the container-name renames (`redis|registry|registryctl|
   nginx → harbor-*`) **baked in** — no runtime `sed`.
3. Commit the static `common/config/*` tree.
4. Pin image tags (already `goharbor/*:v2.14.4`).

### Phase 2 — externalize secrets (the real work)
Replace the secret values that `prepare` baked into `common/config/*/env` with
references resolved from `.env` at compose time:
- Harbor reads most secrets from env (`HARBOR_ADMIN_PASSWORD`, db password,
  `core` secretkey, jobservice secret, CSRF key). Move each into the servarr
  `.env.sops` and feed via the compose `env_file`/`environment`.
- `TODO(erik)`: confirm the full secret set Harbor needs in env vs. files —
  `db/env`, `core/env` (`SECRET_KEY`, `CSRF_KEY`), `jobservice/env`,
  `registry`/`registryctl` HTTP secret. Some (the registry token-service TLS
  key) `prepare` generates per-install — decide: regenerate-once-and-commit-as-
  sops vs. a tiny `ExecStartPre` that mints missing keys idempotently.

### Phase 3 — wire into homelab.compose
1. Add `"harbor"` to `modules/hosts/discovery/compose.nix` `stacks`.
2. **Delete `harbor-setup.sh`** (installer/prepare/sed all gone).
3. `harbor-proxycache.sh` (proxy-cache project creation) is data-plane, not
   deploy — `TODO(erik)`: keep as a documented one-shot, or fold into a
   `harbor-init` oneshot that runs once after first `up` (idempotent API call).

### Phase 4 — version bumps become a reviewable diff
On a Harbor upgrade: re-run `prepare` for the new version, diff the regenerated
compose/config into the committed copy, bump image tags. A deliberate git
change, not a runtime fetch. `TODO(erik)`: a small `just harbor-regen <ver>`
helper to regenerate + show the diff keeps this low-friction.

## Tradeoffs / open decisions (`TODO(erik)`)

- **Re-capture on every Harbor bump** is the standing cost. It's a reviewed git
  diff (declarative + auditable) rather than a runtime surprise — acceptable, or
  too much toil vs. the imperative installer? (lean: acceptable; bumps are rare.)
- **Secret-bearing generated keys** (registry token TLS key): commit-as-sops vs.
  idempotent mint-if-missing. Mint-if-missing keeps one tiny imperative edge but
  avoids committing a generated keypair.
- **Scope check:** is full Harbor still worth this vs. `registry:2` (one trivially
  declarative service)? This RFC assumes the earlier decision (full Harbor) holds.

## Alternatives considered

- **Bespoke `systemd.services.harbor` oneshot (render → prepare → up on switch).**
  Declarative, but invents a second orchestration model on a host that already
  has `homelab.compose`. Rejected — fit the existing mechanism instead.
- **Hand-write the compose + all config from scratch (no installer ever).**
  Maximally pure but brittle + version-coupled; throws away `prepare`'s
  correctness. Rejected.
- **NixOS `virtualisation.oci-containers` for all 9 services.** Same
  config-generation problem as hand-writing, in Nix. Rejected.

## End state

`harbor.yml` + `config/harbor/common/*` committed in servarr, secrets in
`.env.sops`, `"harbor"` in `homelab.compose.stacks`. `harbor-setup.sh` deleted.
Harbor comes up on boot/switch via the same `servarr-pull` + compose-unit chain
as every other stack — reproducible from git, no installer, no manual step.
