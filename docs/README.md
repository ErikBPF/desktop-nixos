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
| [`reference/harbor-discovery-registry.md`](reference/harbor-discovery-registry.md) | Harbor registry on discovery — the imperative baseline. | As-built (proxy-cache + push, 2026-06-29) |
| [`reference/vault-disaster-recovery.md`](reference/vault-disaster-recovery.md) | OpenBao DR runbook — sealed/corrupt/total-loss recovery; the fresh-cluster restore (unseal with the OLD sops key) tested 2026-06-29. | As-built (tested) |
| [`reference/key-rotation.md`](reference/key-rotation.md) | When (and when not) to rotate each fleet key/secret + how — trigger-driven, weighted by blast radius; the age key, escrow passphrase, voyager REST creds, restic/OpenBao keys. | Reference |
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
| [`implemented/2026-06-28-cloudflare-token-terraform-migration.md`](implemented/2026-06-28-cloudflare-token-terraform-migration.md) | ✅ Implemented (2026-06-30) — Cloudflare tokens Terraform-managed in homelab-iac (least-scope, rotatable); one bootstrap token stays manual. Ph3 adopted the HA tunnel via `ignore_changes=[secret]` (write-only secret, no rotation/outage). |
| [`proposals/2026-06-29-grafana-fleet-monitoring.md`](proposals/2026-06-29-grafana-fleet-monitoring.md) | Proposal (skeleton, `TODO`) — complete Grafana monitoring: host health, per-host container stacks (docker/podman), k3s cluster; all alerting to Discord. |
| [`implemented/2026-06-29-repo-ssot-srp.md`](implemented/2026-06-29-repo-ssot-srp.md) | ✅ Implemented (2026-06-29) — SSOT per fact + SRP per repo across the 8-repo ecosystem. P0/P1/P2/P3/P5 (`fleet.json` topology+domains SSOT, consumers live in justfile + homelab-iac + servarr drift-check; CLAUDE.md ownership map + D1–D9 + SRP tree) + **P4** (kindle-dash → standalone OSS, `ghcr.io/erikbpf/kindle-dash` + Harbor `library` mirror, servarr pins the digest). |
| [`proposals/2026-06-29-vault-secrets-platform.md`](proposals/2026-06-29-vault-secrets-platform.md) | Proposal (sub-RFC of SSOT P3, `TODO`) — platform Vault as runtime-secret SSOT (docker via vault-agent, k8s via ESO, iac via provider), sops as root-of-trust/bootstrap; reposition the in-cluster Vault to discovery; webhook as the proof migration. |
| [`proposals/2026-06-29-vault-backup-plan.md`](proposals/2026-06-29-vault-backup-plan.md) | Proposal (gate P3.0, `TODO`) — prove Vault backup+restore before any real secret: raft snapshot → restic (off-site, apart from unseal key) → textfile dead-man's-switch → Grafana/Discord; mock-state restore drill, then migrate. |
| [`implemented/2026-06-30-openbao-root-recovery.md`](implemented/2026-06-30-openbao-root-recovery.md) | ✅ Executed (2026-06-30) — recovered the lost OpenBao root token: temporarily re-enabled `generate-root` (disabled by default ≥2.5.0) via the listener, minted a new root from the unseal key, resealed sops (root + snapshot token, fixing the broken backup, + approle secret-id), sealed the kindle-dash robot secret, re-disabled. Non-destructive. |
| [`implemented/2026-06-29-codex-flake.md`](implemented/2026-06-29-codex-flake.md) | ✅ Implemented (2026-06-30) — reusable `codex-flake` Home Manager profile module for global Codex `AGENTS.md`, inline RTK guidance, caveman style, opt-in generated RTK, opt-in `config.toml`, FlakeHub publish+verify, and desktop laptop consumption. |
| [`proposals/2026-06-30-codex-flake-update-strategy.md`](proposals/2026-06-30-codex-flake-update-strategy.md) | Proposal — decide whether `codex-flake` stays profile-only or grows an optional fast Codex package/update lane analogous to `claude-code-nix`. |
| [`proposals/2026-06-30-hermes-flake-update-hardening.md`](proposals/2026-06-30-hermes-flake-update-hardening.md) | Proposal — harden `hermes-flake`'s existing automated upstream bump strategy: action pins, safer rollback, state-derived tags, richer PR context, and consumer trust modes. |
| [`implemented/2026-06-29-discovery-resilience-fixes.md`](implemented/2026-06-29-discovery-resilience-fixes.md) | ✅ Implemented (core, 2026-06-29) — pull-servarr reset-hard, swag-cert-monitor, AdGuard mem fix. P1-1 (compose drift) + P2 (instability root-cause) remain. |
| [`implemented/2026-06-29-session-landing-plan.md`](implemented/2026-06-29-session-landing-plan.md) | ✅ Done (2026-06-29) — landed the session's deployed/applied work onto main across all three repos. |
| [`implemented/2026-06-30-sccache-shared-cache.md`](implemented/2026-06-30-sccache-shared-cache.md) | ✅ Implemented (2026-06-30) — shared sccache WebDAV cache on orion over the tailnet for dev-loop `cargo build`; cache mode (local compile fallback), opt-in client (enabled on laptop), ACL opened fleet-wide in homelab-iac. `sccache-dist` CPU offload deferred. |
| [`implemented/2026-06-30-deploy-rs-as-deploy-standard.md`](implemented/2026-06-30-deploy-rs-as-deploy-standard.md) | ✅ Implemented (2026-06-30) — deploy-rs (magic rollback) is the fleet remote-switch standard; two-phase toolchain (install + switch). `switch-<host>`→deploy-rs (GPU hosts via `deploy-rs-boot`+reboot), `provision` for new remote hosts; nixos-anywhere/nixos-infect keep first install. Rollout: orion/discovery/kepler done, archinaut in progress, telstar pending A1 capacity. |
| [`implemented/2026-06-30-offsite-dr-crown-jewels.md`](implemented/2026-06-30-offsite-dr-crown-jewels.md) | ✅ Implemented (2026-06-30) — Oracle `voyager` is the off-premise DR anchor for the crown-jewel config tier: 4b passphrase-age escrow of the sops age key (closes the single-point-of-loss), 4a tf state → voyager append-only REST, 4c GitHub-independent `.env.sops` bundle, 4d OpenBao snapshot → voyager. Post-grill hardening §11; pending age-key rotation tracked in `reference/key-rotation.md`. |

> The original dendritic-migration design (`superpowers/specs/2026-03-18-…`) was
> **deleted** from the tree; it is recoverable from git history. The reorg
> proposal decides whether to restore it under `implemented/` or replace it with
> a short dendritic-contract note.

New design work: add an RFC under `proposals/` named
`YYYY-MM-DD-<slug>.md`; promote decisions to ADRs once locked.
