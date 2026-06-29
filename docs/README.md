# docs/

Map of repo documentation. Recipes in `justfile` are the source of truth for
operations; docs explain *why* and capture designs. If a doc and a recipe
disagree, the recipe wins — flag the doc as stale.

**Status is fact-based:** a row marked *Implemented* names the artifact that
actually shipped. *Proposal* / *Plan* / *Backlog* = not built. *In progress* =
partially applied. Statuses mirror each doc's own `**Status:**` line.

> This tree was reorganized per
> [`proposals/2026-06-26-docs-reorg-and-install.md`](proposals/2026-06-26-docs-reorg-and-install.md):
> `guides/` (install, obsidian), `reference/` (operational docs), `implemented/`
> (shipped designs), `proposals/` (active RFCs only), and a `docs-check` link
> gate wired into `just check`.

## Operational references

| Doc | Covers | Status |
|-----|--------|--------|
| [`reference/dendritic-contract.md`](reference/dendritic-contract.md) | The rules a `modules/` file must follow (registration, naming, `_` helpers). Enforced by `just structure-check`. | Reference |
| [`reference/kepler-ai-serving.md`](reference/kepler-ai-serving.md) | AI inference topology on kepler: LiteLLM routing, TTS/whisper services, ports. Cross-check before touching voice wiring in `home-assistant-config`. | Reference |
| [`reference/kepler-zfs-setup.md`](reference/kepler-zfs-setup.md) | Imperative ZFS pool creation on kepler (pools are *not* in disko). Needed when reprovisioning or adding bulk-pool. | Reference |
| [`reference/kepler-k3s-platform-status.md`](reference/kepler-k3s-platform-status.md) | As-built status of the kepler k3s cluster + `homelab-gitops` workloads: topology, what's implemented/validated, next steps, cluster gotchas. | As-built |
| [`reference/harbor-discovery-registry.md`](reference/harbor-discovery-registry.md) | Harbor registry on discovery — the imperative baseline. | Prepared, not yet deployed |
| [`guides/obsidian.md`](guides/obsidian.md) | Obsidian + sync configuration for the desktop hosts. | Guide |
| [`guides/install.md`](guides/install.md) | Host bootstrap walkthrough (nixos-anywhere / ISO paths). | Guide |

## Designs and proposals

| Doc | Status |
|-----|--------|
| [`proposals/2026-05-23-home-assistant-declarative.md`](proposals/2026-05-23-home-assistant-declarative.md) | Proposal — declarative HA management. |
| [`proposals/2026-05-27-home-assistant-voice-assistant.md`](proposals/2026-05-27-home-assistant-voice-assistant.md) | Proposal — HA voice assistant (Phase 1 branch lives in `home-assistant-config`). |
| [`implemented/2026-06-16-printer-nixos-host.md`](implemented/2026-06-16-printer-nixos-host.md) | ✅ Implemented (2026-06-21) — BIQU B1 Klipper host `archinaut`. |
| [`proposals/2026-06-19-kepler-k3s-microvm-cluster.md`](proposals/2026-06-19-kepler-k3s-microvm-cluster.md) | Proposal (grilled twice) — kepler k3s MicroVM cluster. |
| [`implemented/2026-06-20-archinaut-kernel-direct-boot.md`](implemented/2026-06-20-archinaut-kernel-direct-boot.md) | ✅ Implemented (2026-06-21) — kernel-direct boot on the RPi 3B+. |
| [`proposals/2026-06-20-cluster-homelab-gitops.md`](proposals/2026-06-20-cluster-homelab-gitops.md) | Proposal (skeleton, `TODO`) — `homelab-gitops` sister repo (Argo CD, ESO→Vault). |
| [`proposals/2026-06-20-lazy-trees-determinate-nix.md`](proposals/2026-06-20-lazy-trees-determinate-nix.md) | Plan (skeleton, `TODO`) — lazy-trees / Determinate Nix. |
| [`implemented/2026-06-20-telemetry-hardening.md`](implemented/2026-06-20-telemetry-hardening.md) | ✅ Implemented (2026-06-27) — Grafana/Loki/Prometheus hardening; core was already live, §5 structured-metadata + Logs Drilldown deployed. |
| [`implemented/2026-06-20-unifi-declarative-config.md`](implemented/2026-06-20-unifi-declarative-config.md) | ✅ Implemented — declarative UDM config in the `homelab-iac` sister repo. |
| [`proposals/2026-06-22-declarative-implementation-plan.md`](proposals/2026-06-22-declarative-implementation-plan.md) | In progress — Spec/work-items for Harbor + k3s-mirror → declarative. |
| [`implemented/2026-06-22-harbor-declarative.md`](implemented/2026-06-22-harbor-declarative.md) | Implemented — **oneshot variant shipped, not this RFC's static stack**. |
| [`proposals/2026-06-22-harbor-pullthrough-mirror.md`](proposals/2026-06-22-harbor-pullthrough-mirror.md) | Proposal (scoped, not applied). |
| [`proposals/2026-06-24-hermes-memory-skills.md`](proposals/2026-06-24-hermes-memory-skills.md) | Partially implemented (§9 is the authoritative record). |
| [`proposals/2026-06-24-repo-structure-improvements.md`](proposals/2026-06-24-repo-structure-improvements.md) | Proposal — tighten the dendritic module structure. |
| [`proposals/2026-06-24-source-backed-host-improvements.md`](proposals/2026-06-24-source-backed-host-improvements.md) | Proposal — source-backed host security/perf/usability review. |
| [`proposals/2026-06-25-hermes-agentmemory-integration.md`](proposals/2026-06-25-hermes-agentmemory-integration.md) | Plan — **supersedes** `hermes-deferred-plans` §1. |
| [`proposals/2026-06-25-hermes-deferred-plans.md`](proposals/2026-06-25-hermes-deferred-plans.md) | Backlog — partly superseded by `hermes-agentmemory-integration`. |
| [`proposals/2026-06-26-docs-reorg-and-install.md`](proposals/2026-06-26-docs-reorg-and-install.md) | Proposal — this docs reorganization + INSTALL relocation/refresh. |
| [`proposals/2026-06-28-cloudflare-token-terraform-migration.md`](proposals/2026-06-28-cloudflare-token-terraform-migration.md) | Proposal (exploration) — make Cloudflare API tokens Terraform-managed in homelab-iac (least-scope, rotatable); one bootstrap token stays manual. |
| [`implemented/2026-06-29-discovery-resilience-fixes.md`](implemented/2026-06-29-discovery-resilience-fixes.md) | ✅ Implemented (core, 2026-06-29) — pull-servarr reset-hard, swag-cert-monitor, AdGuard mem fix. P1-1 (compose drift) + P2 (instability root-cause) remain. |
| [`implemented/2026-06-29-session-landing-plan.md`](implemented/2026-06-29-session-landing-plan.md) | ✅ Done (2026-06-29) — landed the session's deployed/applied work onto main across all three repos. |

> The original dendritic-migration design (`superpowers/specs/2026-03-18-…`) was
> **deleted** from the tree; it is recoverable from git history. The reorg
> proposal decides whether to restore it under `implemented/` or replace it with
> a short dendritic-contract note.

New design work: add an RFC under `proposals/` named
`YYYY-MM-DD-<slug>.md`; promote decisions to ADRs once locked.
