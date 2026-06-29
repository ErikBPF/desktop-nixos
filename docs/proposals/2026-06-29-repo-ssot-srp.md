# Repo ecosystem — single source of truth (SSOT) & single responsibility (SRP)

**Status:** Plan — core decisions **locked 2026-06-29** (see *Locked decisions*);
per-SSOT implementation plans below. A few low-risk items keep proposed defaults
marked `TODO(erik)`.
**Date:** 2026-06-29
**Audience:** Maintainers of the whole homelab repo set
**Post-read action:** Decide the ownership boundaries + the `TODO(erik)` forks
(topology SSOT mechanism, new-workload default, secret boundary, consolidation
targets), then split into per-repo work items.

## Why now

Two forces make this worth settling:
1. **The k3s cluster is live** (kepler, 3 CP). There are now *two* ways to ship a
   workload — `servarr` (compose) and `homelab-gitops` (k8s/Argo CD) — with no
   rule for which to use. That ambiguity compounds with every new service.
2. Recent work kept tripping on **duplicated truth** — host IPs in 3+ places, the
   Discord webhook now in two secret stores, CLAUDE.md claiming "five sister
   repos" when there are **eight**. Each duplication is a future drift bug.

Goal: one **owner per concern** (SRP) and one **source per fact** (SSOT), plus a
consolidation roadmap for what should be absorbed.

## Current repo map (as-built, verified 2026-06-29)

Eight repos plug into `desktop-nixos` (symlinked under `references/repos/`):

| Repo | Responsibility (intended SRP) | Artifact / runtime |
|------|-------------------------------|--------------------|
| **desktop-nixos** | Host OS + fleet system config; **SSOT for hosts/roles** | Nix flake → NixOS |
| **homelab-iac** | Network substrate: UniFi VLAN/WLAN/**DHCP reservations**/static DNS, Tailscale ACL, Cloudflare tokens | OpenTofu/Terragrunt |
| **servarr** | Container deployments via **compose** (discovery/orion + kepler non-k8s) | docker/podman compose |
| **homelab-gitops** | **k8s** workloads via Argo CD; ESO→Vault@discovery | k8s manifests / Argo |
| **hermes-flake** | hermes-agent **software** (package + NixOS module) | flake input |
| **hermes-skills** | hermes **skill content** (mounted into the agent) | files, git-synced |
| **home-assistant-config** | HA **app config** | YAML, host pulls |
| **klipper-biqu** | Printer (Klipper/OrcaSlicer) **config/state** | files |
| **kindle-dash** | Kindle e-ink dashboard | spans servarr + flake + device |

The infra "stack" is really **three clean layers** — worth stating explicitly:
network/physical (`homelab-iac`) → host/cluster substrate (`desktop-nixos`,
incl. the k3s microvms) → workloads (`servarr` compose **and** `homelab-gitops`
k8s). The workload layer is the one that's split.

## SSOT audit — facts with more than one source

1. **Fleet addressing (worst offender).** Host IPs live in: `desktop-nixos`
   `justfile` (`ip_*`) + each host's `networking.nix` + `homelab-iac` DHCP
   reservations + AdGuard DNS rewrites. CLAUDE.md already documents the manual
   "change both repos" dance — that *is* the smell. One IP change = ≥3 edits.
2. **Service domains / hostnames.** `meta.domain` (flake) + SWAG subdomains
   (servarr) + AdGuard rewrites + Cloudflare records (iac) + k8s ingress
   (gitops). No single place answers "what hostnames exist and where do they
   resolve."
3. **Secrets — four stores.** sops `secrets.yaml` (desktop-nixos), sops
   `.env.sops` (servarr), `.env` (homelab-iac), **Vault** via ESO (gitops). The
   Discord webhook just landed in **both** desktop-nixos sops *and* servarr
   `.env.sops` — a duplication created this week. No boundary rule.
4. **The repo inventory itself.** CLAUDE.md "Cross-repo synergies" lists *five*
   sister repos; there are *eight* (`hermes-skills`, `homelab-gitops`,
   `kindle-dash` undocumented there). The map drifted from reality.

## SRP audit — concerns with ambiguous/split ownership

1. **`servarr` vs `homelab-gitops`** — both own "deploy a workload," split only
   by runtime. No rule for where a new service goes. **The central question.**
2. **`kindle-dash`** — container half (servarr), build glue (flake), device
   scripts — no single owner. Classic absorb candidate.
3. **`hermes-flake` + `hermes-skills`** — two repos for one agent (software vs
   content). Defensible (package ≠ content), but worth a conscious call.
4. **Cloudflare tokens** — `homelab-iac` is meant to own them (per the
   cloudflare-token RFC), yet SWAG's token lives in servarr `.env.sops`.

## Proposed direction (options — `TODO(erik)`)

### SSOT mechanisms
- **Topology SSOT.** Define hosts once — `{name, ip, mac, role, services}` — and
  have everyone consume it. Options: (a) a Nix attrset in `desktop-nixos`
  (extend `modules/meta.nix`) exported to JSON that `homelab-iac` reads for
  reservations + AdGuard; (b) a standalone tiny data repo both consume;
  (c) `homelab-iac` authoritative (it owns DHCP/DNS) and exports to the flake.
  *Lean:* (a) — the flake already centralizes `username`/`domain`; addressing is
  the same shape, and Terragrunt can read a generated JSON. `TODO(erik)`.
- **Domains/hostnames SSOT.** Derive subdomain → backend from the topology
  source; SWAG/AdGuard/Cloudflare/ingress become *generated consumers*, not
  hand-authored lists. `TODO(erik)`: how far to push generation.
- **Secret boundary.** Converge **runtime** secrets on **Vault** (already present
  for k8s); keep **build/host** secrets in sops (needed at eval/activation).
  Kill the Discord-webhook duplication: one source, others reference. `TODO(erik)`:
  Vault-as-runtime-SSOT scope + the host↔container sharing pattern.

### SRP boundaries (target — one owner per concern)
Crisp ownership table (network → iac; OS/cluster-substrate → nixos; k8s workloads
→ gitops; compose workloads → servarr *until migrated*; app configs → their
repos; agent software → hermes-flake). Write it into CLAUDE.md and keep it true.

### Consolidation roadmap (what absorbs what)
**Corrected 2026-06-29:** `servarr` and `homelab-gitops` are **peer permanent
environments**, not a migration — `servarr` *owns the home env* (household
services: plex, adguard, backups) and stays; `homelab-gitops` *owns the lab env*
(production-mimic study). New work is placed by **purpose**, not absorbed:
- **Household / always-on home service** → `servarr` (compose).
- **Study / prod-mimic / ephemeral experiment** → `homelab-gitops` (k8s; vcluster
  for throwaways).
- **`kindle-dash`** → becomes a **standalone OSS project**: it owns its
  container build + scripts and publishes the image (GHCR public + Harbor
  private); consuming stacks only *reference* the image and document usage. Strip
  homelab-specific deploy glue out of it.
- **Cloudflare tokens** — `homelab-iac` owns; consumers reference.
- **`hermes-skills`** — keep separate (content ≠ package). `TODO(erik)` if ever
  noisy.

## Locked decisions (2026-06-29)

| # | Decision |
|---|----------|
| D1 | **Two peer envs:** home (`servarr`, household) + lab (`homelab-gitops`, prod-mimic study). Not a migration; placed by purpose. |
| D2 | **Lab is self-contained:** own in-cluster Prometheus/Grafana/ingress/CoreDNS. Home keeps servarr/discovery. Only the **network** is shared. |
| D3 | **Ephemeral lab workloads = vcluster** (virtual clusters in the one k3s; delete = teardown). |
| D4 | **Lab on the home LAN** (no dedicated VLAN for now). |
| D5 | **One shared platform Vault** = runtime-secret SSOT (docker via vault-agent, k8s via ESO, iac via Vault provider). **sops = root-of-trust + host/build/bootstrap only.** |
| D6 | **VMs stay Nix-native** in `desktop-nixos` (microvm.nix). `homelab-iac` = network only. "Cluster substrate" is its own documented layer. |
| D7 | **Images:** Harbor = private SSOT both envs pull; GHCR = public for OSS (kindle-dash). |
| D8 | **kindle-dash = standalone OSS** — owns build+scripts, publishes image; stacks only reference it. |
| D9 | **Atomicity contract = publish-and-pin.** SSOT owner publishes a versioned artifact; consumers vendor/pin it. No live cross-repo reads at build/apply. Runtime secret fetch from Vault is the one allowed *runtime* dependency. |

Proposed defaults for the still-soft items (override if wrong): TF state stays in
MinIO@discovery (bootstrap-tier, accepted); **lab cluster state is not backed up**
(rebuildable from gitops); **no home↔lab promotion** (isolated envs).

## Bootstrap / DR order (the backbone atomicity rests on)

Rebuild-from-zero sequence — also the dependency order that keeps repos atomic:

1. **Root of trust** — sops **age key** (restored from offline/break-glass).
2. **Network** — `homelab-iac` apply (VLANs/DHCP/DNS/Tailscale).
3. **Hosts + cluster substrate** — `desktop-nixos` deploy (OS, NFS, k3s microvms).
4. **Platform** — **Vault** (unseal via sops bootstrap), then Argo CD + lab obs.
5. **Workloads** — home: `servarr` git pull; lab: Argo syncs `homelab-gitops`.

Each layer depends only on the ones above it, and only on their **published
artifacts** — so any single repo rebuilds against pinned inputs without the
others present.

## Implementation plans (per SSOT concern)

Each follows publish-and-pin (D9). Ordered by drift-risk ÷ effort.

### P0 — Repo-map + SRP ownership table (SSOT: the inventory) · *S*
- **Own:** `desktop-nixos` CLAUDE.md "Cross-repo synergies".
- **Do:** rewrite to the **8 repos** + the home/lab/platform/substrate model + a
  one-owner-per-concern table; add the D1–D9 summary. Add a one-line "owns X /
  consumes Y (pinned)" header to each sister repo's README.
- **Atomic:** doc-only. **Verify:** `just docs-check`; table matches
  `references/repos/`.

### P1 — Fleet topology / addressing SSOT · *M*
- **Author:** `desktop-nixos` — extend `modules/meta.nix` with
  `fleet.hosts.<name> = { ip; mac; role; tailscaleIp?; }`. Host `networking.nix`
  consume it natively.
- **Publish:** flake output `fleet` → `nix eval .#fleet --json` committed as
  `fleet.json` (the pinned artifact).
- **Consume (vendor/pin):** `justfile` `ip_*` derive from it; `homelab-iac`
  reservations + AdGuard static DNS read a **vendored** `fleet.json`
  (`jsondecode(file(...))`), re-synced on a deliberate bump.
- **Atomic:** iac builds against its pinned snapshot. **Verify:** `just dry`
  hosts + iac `plan` clean; change one IP → regenerate → both consumers reflect.

### P2 — Domains / hostnames SSOT · *M* (after P1)
- **Author:** extend the fleet artifact with `services.<sub> = { host; port;
  scope = home|public }`. **Lab hostnames live in `homelab-gitops`** (D2,
  self-contained) — *not* here; this source covers home + public + cross-env only.
- **Consume:** SWAG proxy-confs (home), AdGuard rewrites + Cloudflare records
  (iac) become **generated** from the artifact, not hand-authored.
- **Verify:** generated configs diff-clean vs current; a new home service needs
  one edit (the source), not four.

### P3 — Secrets SSOT: platform Vault + sops bootstrap · *L* (own sub-RFC)
- **Stand up** the platform Vault (auto-unseal; unseal key + root token →
  **sops**, the only bootstrap secret it needs). Position: a **platform** service
  (runs on discovery for now, labelled platform, not "home").
- **Boundary doc:** sops = host SSH/age keys, unit-baked secrets (wifi/restic),
  Vault bootstrap, iac bootstrap token. Vault = everything a *running* workload
  reads.
- **Wire consumers:** k8s ESO (exists) · **docker/compose** via **vault-agent**
  rendering `.env` (replaces `.env.sops` per stack) · **host systemd** via
  vault-agent for cross-boundary secrets · **iac** via the Vault provider.
- **Proof migration:** move the **Discord webhook** sops→Vault; host (vault-agent)
  and containers both read it from Vault; **delete the two sops copies** — kills
  the duplication created this week.
- **Atomic:** build/activation still sops (offline-safe); runtime fetch from Vault
  is the one sanctioned runtime dep (D9). **Verify:** each consumer renders its
  secret; webhook fires from the Vault value; `nixos-rebuild` still works with
  Vault down (sops bootstrap intact).
- Phased: Vault up → webhook proof → compose `.env` → iac tokens → shrink sops.

### P4 — Image / artifact SSOT: Harbor + GHCR · *M*
- **kindle-dash:** CI builds → publish to **GHCR** (public OSS) + push/mirror to
  **Harbor** (private). Strip homelab deploy glue; keep build + scripts; document
  usage (env/ports) in its README. It must `git clone && build` standalone.
- **Consumers** (servarr/gitops): reference the **pinned digest** + supply their
  own deploy config. Harbor proxy-cache already exists (harbor RFC).
- **Verify:** kindle-dash builds standalone; servarr references the published
  tag; image pulls on both envs.

### P5 — SRP placement rule (no absorption) · *S*
- Write the **placement decision tree** (D1): household/always-on → `servarr`;
  study/prod-mimic/ephemeral → `homelab-gitops` (+ vcluster). No forced migration
  of existing home stacks. Record in CLAUDE.md alongside P0.

## Non-goals

- Not a rewrite. SRP/SSOT is enforced by **moving ownership + generating
  consumers**, one concern at a time, each behind a dry-build/plan.
- Not forcing everything onto k8s — host-bound infra (DNS, ingress, device
  controllers) legitimately stays on its host.

## Links

- `proposals/2026-06-20-cluster-homelab-gitops.md` (the gitops repo),
  `proposals/2026-06-28-cloudflare-token-terraform-migration.md` (token
  ownership), `reference/kepler-k3s-platform-status.md`, and the CLAUDE.md
  "Cross-repo synergies" map (which this RFC would correct).
