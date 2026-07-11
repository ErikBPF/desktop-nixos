---
title: Discovery resilience — persistent fixes from the SWAG cert incident
status: Implemented (core, 2026-06-29)
date: 2026-06-29
audience: Maintainers of desktop-nixos + servarr
post-read-action: P1-1 (compose drift) remains. P2-1 root-caused + fixed 2026-07-06 (e1000e TX hang). Tracked below.
---

# Discovery resilience — persistent fixes

> **Implemented 2026-06-29:** **P0-1** swag-cert-monitor (`modules/services/swag-cert-monitor.nix`,
> ntfy on expiry/health) + SWAG cert-gate comment + Terraform swag-dns01 token;
> **P0-2** `just pull-servarr` (git fetch + **reset --hard origin/main**,
> retires the rsync overlap) + `just kick-stack`; **P1-2** AdGuard `mem_limit`
> 512m→1.5g (the OOM that took LAN DNS down). **P2-1 (instability root-cause)**
> resolved 2026-07-06: e1000e TX Hardware Unit Hang → TSO/GSO disabled on eno1.
> **Still open:** P1-1 (compose project-name drift / orphan cleanup).

## Context

Chasing "kindle-dash is not on" uncovered a stack of latent problems on
discovery. The visible symptom (every subdomain `000`) was **SWAG down**, and
the chase revealed five distinct fragilities. The outage is now fixed (SWAG
`5.4.0 → 5.6.0-ls467`, cert minted, all subdomains back). This proposal makes
the underlying problems not recur.

## Found problems → persistent fixes

### P0-1. SWAG cert fragility (the incident)

Three compounding causes, only one of which we'd been chasing:
1. **Image bug** — SWAG `5.4.0` ships `certbot-dns-cloudflare` + `cloudflare`
   python `2.19.4` that sends malformed headers for **API-token** auth
   (`Error determining zone_id: 6003`). A *valid* token still failed. **Fixed**
   by bumping to `5.6.0-ls467` (re-pinned).
2. **No cached cert** — `/config/etc/letsencrypt/live/` was empty, forcing a
   live re-mint (so the broken image bit immediately, instead of at renewal).
3. **Token was stale + broad** — the `.env.sops` token was invalid; we set a
   working temp token.

**Persistent fixes:**
- **Cert/SWAG monitoring** — add a Grafana alert (same pattern as the disk-fill
  rule) on **SWAG container health** + **cert expiry** (probe the leaf cert's
  `notAfter`, or scrape `swag`/blackbox). Today a dead cert is silent until
  something hits a subdomain. `TODO(erik)`: blackbox-exporter probe vs a small
  cert-expiry script → ntfy.
- **Post-bump cert gate** — any SWAG image bump must verify the cert re-mints
  before it's considered done (a SWAG bump can re-break token DNS-01). Add to the
  image-update runbook / renovate post-merge check.
- **Least-scope token** — finish the Terraform `swag-dns01` token (the
  `cloudflare-token-terraform-migration` RFC). Now unblocked-ish: SWAG is up, so
  the iac state backend (MinIO behind SWAG) is reachable again; still gated on the
  iac token genuinely getting `API Tokens:Edit`. ~~**Revoke the temp token**
  (`cfut_9tU2…`, pasted in chat) once swag-dns01 lands.~~ **Done** — revoked
  2026-06-29 (migration RFC Ph1+2); API-verified 2026-07-01: the account holds
  only `Homelab IAC` (bootstrap) + `swag-dns01`, no strays (Ph4 sweep clean).

### P0-2. Deploy pipeline conflict (rsync vs git-pull)

**Root cause of the deploy breakage:** `just sync-servarr` (rsync) writes into
`/home/erik/servarr` — the *same* tree `servarr-pull` git-manages. That dirties
the working tree, so `servarr-pull`'s `git pull --ff-only origin main || true`
**silently fails** (the `|| true` swallows it) → the host never gets new commits.
We worked around it with surgical `git checkout origin/main -- <file>`.

**Persistent fix (`TODO(erik)` — pick one, recommend both):**
- (a) **Make `servarr-pull` authoritative**: replace `git pull --ff-only … ||
  true` with `git fetch origin main && git reset --hard origin/main` so the host
  tree always matches git, regardless of local drift. Drop the silent `|| true`.
- (b) **Stop rsync-into-the-clone**: retire `sync-servarr`'s overlap — either
  point it at a non-git path, or remove it in favour of git-only delivery
  (`servarr-pull`). **One** host-delivery mechanism, not two writing one dir.
- Net: git is the single source→host path; rsync no longer fights it.

### P1-1. Compose project-name drift / duplicate containers

`docker-compose up` spawned/conflicted duplicate containers (`k8s-apiserver`,
`swag-init`) because manual invocations and the `podman-compose-<stack>` systemd
unit don't share a consistent `--project-name` — so the networking unit can't
`up` cleanly (it aborts on the name conflict). `containers.nix` already warns
about this.

**Persistent fixes:**
- **Consistent project name** — every manual op uses the unit's
  `--project-name <stack>`; or stop ad-hoc `docker-compose` and drive everything
  through the NixOS `homelab.compose` units.
- **Clean the orphans** — remove the stale `k8s-apiserver` (and any other
  duplicate) so `podman-compose-networking.service` starts green; add
  `--remove-orphans` to the unit's `ExecStart`.
- `TODO(erik)`: is `k8s-apiserver` in the networking stack still wanted? It's
  been a recurring conflict.

### P1-2. DNS self-dependency

`servarr-pull` failed earlier on `Could not resolve github.com`. Discovery's
primary nameserver is its **own** AdGuard container (`192.168.10.210`); when
AdGuard/discovery flaps, host system DNS dies → git pulls, image pulls, and
certbot all fail. `resolved` has `FallbackDNS` (UDM + public) but it clearly
isn't catching every window.

**Persistent fix:** give the **host's own system resolution** a non-self path
(don't route discovery's *system* DNS solely through the container it hosts) —
e.g. resolved with the UDM/public as primary for the host, AdGuard for LAN
clients; or verify `FallbackDNS` actually engages promptly on AdGuard downtime.
`TODO(erik)`: confirm the desired split (host vs client DNS).

### P2-1. Discovery instability (the root symptom) — **root-caused 2026-07-06**

Discovery has been rebooting repeatedly (uptime 2–9 min across this session).
The **`discovery-diagnostics`** module (persistent 2 GB journal + `net-watch` +
2-min sysstat) was deployed for exactly this — it now survives reboots and
captured the cause.

**Root cause (from `journalctl -b -1`):** the onboard Intel NIC's `e1000e`
driver wedges its TX ring — repeated `e1000e 0000:00:19.0 eno1: Detected
Hardware Unit Hang` (TDH/TDT desync) every 2 s. Transmit stops, the whole host
drops off the network until it reboots. Classic long-standing e1000e bug on this
PCH-LM-class controller, triggered by the TSO/GSO segmentation-offload path.

**Fix (deployed 2026-07-06):** disable TCP/generic segmentation offload on eno1
via a udev `.link` matched by MAC — `systemd.network.links."10-eno1-no-tso"` in
`modules/hosts/discovery/networking.nix`. Segmentation moves to the kernel,
which sidesteps the offending hardware path. Cost is a few % of one core under
sustained line-rate transfer (negligible at this host's gigabit workload); GRO
(receive) left on since the hang is a transmit bug. Applies on next device
add/boot; on a live host apply immediately with
`ethtool -K eno1 tso off gso off`. Watch for recurrence via `net-watch` +
`journalctl -k -g 'Hardware Unit Hang'`.

### P2-2. Image-update strategy

~25 images are hand-pinned semver; "update all" by hand is breaking-change-prone
and there's already a **renovate** stack for this. The `:latest` bump used to fix
SWAG was reverted to a pin.

**Persistent fix:** controlled updates via **renovate PRs** (+ digest pinning),
not manual/blind bumps. Verify renovate is actually running on discovery (it may
have stalled during the instability). A blind all-stack bump mid-instability is
explicitly *not* recommended.

## Priority / sequence

1. **P0** — SWAG re-pin (**done**) · deploy-pipeline reconciliation (P0-2,
   **done** — `servarr-pull` now `fetch + reset --hard`, rsync recipes
   `sync-servarr`/`sync-stack` retired for git-only `prep-servarr` →
   `pull-servarr` → `kick-stack`; staged, not yet deployed) · cert/SWAG
   monitoring (P0-1, **done** — `swag-cert-monitor` module: daily :443 TLS
   probe → ntfy on dead handshake or <14d expiry; cert gate comment added to
   the SWAG image pin; staged, not yet deployed).
2. **P1** — compose project-name hygiene + orphan cleanup (P1-1) · host DNS
   split (P1-2).
3. **P2** — instability root-cause from diagnostics data (P2-1) · renovate-driven
   image updates + swag-dns01 least-scope token + **revoke the temp token**.

## Verify (per fix)

- Pipeline: edit a servarr file → push → `servarr-pull` → host tree matches
  origin with no manual checkout.
- Compose: `systemctl --user restart podman-compose-networking.service` exits 0
  (no name conflict).
- SWAG monitoring: expire-soon test fires an ntfy alert.
- Cert: `docker exec swag ls /config/etc/letsencrypt/live/` present;
  `curl https://kindle.homelab…/dash.png` → 200 (the canary).
