# Repo ecosystem — single source of truth (SSOT) & single responsibility (SRP)

**Status:** Proposal (exploration — judgment marked `TODO(erik)`)
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
- **`servarr` → `homelab-gitops` (gradual).** With k8s live, **new stateless
  workloads default to k8s (gitops)**; `servarr` retains only host-bound /
  not-yet-migrated stacks (discovery DNS/ingress/SWAG, host-pinned services).
  Long-term `servarr` shrinks toward absorption. `TODO(erik)`: migration criteria
  + what is *intentionally* host-bound and stays in compose forever.
- **`kindle-dash`** — move the container half into the workload owner (servarr or
  gitops), keep device scripts in its own repo; stop spanning three.
- **`hermes-skills`** — keep separate (content) or fold into `hermes-flake`.
  `TODO(erik)`.
- **Cloudflare tokens** — finish moving to `homelab-iac` ownership (the
  cloudflare-token RFC); servarr *consumes*, doesn't own.

## Decisions `TODO(erik)`

1. Topology SSOT mechanism + which repo is authoritative for addressing.
2. New-workload default: **k8s (gitops)** vs compose (servarr); migration trigger.
3. Secret SSOT: Vault scope for runtime vs sops for build/host; de-dupe webhook.
4. `servarr` end-state: mostly-absorbed vs retained for host-bound stacks.
5. `kindle-dash` / `hermes-skills` consolidation.
6. First concrete step (recommend: fix the repo-map in CLAUDE.md + pick the
   addressing SSOT — highest drift-risk, lowest effort).

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
