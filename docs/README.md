# docs/

Map of repo documentation. Recipes in `justfile` are the source of truth for
operations; docs explain *why* and capture designs. If a doc and a recipe
disagree, the recipe wins — flag the doc as stale.

## Operational references

| Doc | Covers |
|-----|--------|
| [`kepler-ai-serving.md`](kepler-ai-serving.md) | AI inference topology on kepler: LiteLLM routing, TTS/whisper services, ports. Cross-check before touching voice wiring in `home-assistant-config`. |
| [`kepler-zfs-setup.md`](kepler-zfs-setup.md) | Imperative ZFS pool creation on kepler (pools are *not* in disko). Needed when reprovisioning or adding bulk-pool. |
| [`OBSIDIAN_SETUP.md`](OBSIDIAN_SETUP.md) | Obsidian + sync configuration for the desktop hosts. |
| [`../INSTALL.md`](../INSTALL.md) | Host bootstrap walkthrough (nixos-anywhere / ISO paths). |

## Designs and proposals

| Doc | Status |
|-----|--------|
| [`superpowers/specs/2026-03-18-dendritic-migration-design.md`](superpowers/specs/2026-03-18-dendritic-migration-design.md) | Implemented — the current module layout follows this design. Historical reference. |
| [`proposals/2026-05-23-home-assistant-declarative.md`](proposals/2026-05-23-home-assistant-declarative.md) | Proposal — declarative HA management. |
| [`proposals/2026-05-27-home-assistant-voice-assistant.md`](proposals/2026-05-27-home-assistant-voice-assistant.md) | In progress — HA voice assistant (Phase 1 branch lives in `home-assistant-config`). |
| [`proposals/2026-06-16-printer-nixos-host.md`](proposals/2026-06-16-printer-nixos-host.md) | Proposal (skeleton) — BIQU B1 Klipper printer as fleet host `archinaut`; judgment sections pending. |
| [`proposals/archinaut-migration-plan.md`](proposals/archinaut-migration-plan.md) | Execution checklist for the `archinaut` migration (session handoff). Pairs with the RFC above. Printer config/calibration docs live in the `klipper-biqu` sister repo. |
| [`proposals/2026-06-20-unifi-declarative-config.md`](proposals/2026-06-20-unifi-declarative-config.md) | **Implemented** — declarative UDM config via OpenTofu/Terragrunt in the `homelab-iac` sister repo (import-first, zero-diff). |
| [`proposals/2026-06-20-telemetry-hardening.md`](proposals/2026-06-20-telemetry-hardening.md) | Proposal (skeleton) — security/QoL/devex for the push-based Grafana/Loki/Prometheus stack; top-5 + a Loki cardinality fix. |
| [`proposals/2026-06-20-cluster-homelab-gitops.md`](proposals/2026-06-20-cluster-homelab-gitops.md) | Proposal (skeleton) — new `homelab-gitops` sister repo (servarr-style, NOT Nix): Argo CD + Traefik + Harbor + fast/slow NFS + ESO→Vault@discovery + KEDA/OTel/Jaeger. Prod-mimic lab; judgment pending. |

New design work: add an RFC under `proposals/` named
`YYYY-MM-DD-<slug>.md`; promote decisions to ADRs once locked.
