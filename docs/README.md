# docs/

Map of repo documentation. Recipes in `justfile` are the source of truth for
operations; docs explain *why* and capture designs. If a doc and a recipe
disagree, the recipe wins — flag the doc as stale.

**Status is fact-based:** a row marked *Implemented* names the artifact that
actually shipped. *Proposal* / *Plan* / *Backlog* = not built. *In progress* =
partially applied. Statuses mirror each doc's own `**Status:**` line.

> This tree was reorganized per
> [`implemented/2026-06-26-docs-reorg-and-install.md`](implemented/2026-06-26-docs-reorg-and-install.md):
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
| [`reference/voyager-offsite-maintenance.md`](reference/voyager-offsite-maintenance.md) | Voyager append-only restic tier: what lives there, monitoring/alerts, weekly `restic check`, manual prune window, owed restore drill. | As-built (2026-07-01) |
| [`reference/service-exposure.md`](reference/service-exposure.md) | Discovery exposure audit: what's LAN/tailnet/internet-reachable and why — Docker-published ports bypass the NixOS firewall. Re-audit with `just verify-firewall`. | As-built (2026-07-01) |
| [`guides/obsidian.md`](guides/obsidian.md) | Obsidian + sync configuration for the desktop hosts. | Guide |
| [`guides/install.md`](guides/install.md) | Host bootstrap walkthrough (nixos-anywhere / ISO paths). | Guide |

## Designs and proposals

| Doc | Status |
|-----|--------|
| [`proposals/2026-05-23-home-assistant-declarative.md`](proposals/2026-05-23-home-assistant-declarative.md) | Proposal — declarative HA management. |
| [`implemented/2026-05-27-home-assistant-voice-assistant.md`](implemented/2026-05-27-home-assistant-voice-assistant.md) | ✅ Implemented (audit 2026-07-02) — Phases 0–3 core shipped in `home-assistant-config` (LiteLLM STT/TTS, LLM brain, web search, openWakeWord + Atom Echo). §6 synergies are future enhancements (backlog A12). |
| [`implemented/2026-06-16-printer-nixos-host.md`](implemented/2026-06-16-printer-nixos-host.md) | ✅ Implemented (2026-06-21) — BIQU B1 Klipper host `archinaut`. |
| [`implemented/2026-06-19-kepler-k3s-microvm-cluster.md`](implemented/2026-06-19-kepler-k3s-microvm-cluster.md) | ✅ Implemented (core, live) — kepler k3s MicroVM cluster; 3 CP + workers running. |
| [`implemented/2026-06-20-archinaut-kernel-direct-boot.md`](implemented/2026-06-20-archinaut-kernel-direct-boot.md) | ✅ Implemented (2026-06-21) — kernel-direct boot on the RPi 3B+. |
| [`implemented/2026-06-20-cluster-homelab-gitops.md`](implemented/2026-06-20-cluster-homelab-gitops.md) | ✅ Implemented (audit 2026-07-02) — `homelab-gitops` sister repo live: 14 Argo CD apps Synced+Healthy on kepler k3s (Argo self-managed, in-cluster Vault+ESO, csi-driver-nfs, Traefik, Harbor, KEDA, Jaeger+OTel). Remaining `TODO`s are enhancements (external-dns, dual tracing sinks, multi-cluster). |
| [`proposals/2026-06-20-lazy-trees-determinate-nix.md`](proposals/2026-06-20-lazy-trees-determinate-nix.md) | Plan (skeleton, `TODO`) — lazy-trees / Determinate Nix. |
| [`implemented/2026-06-20-telemetry-hardening.md`](implemented/2026-06-20-telemetry-hardening.md) | ✅ Implemented (2026-06-27) — Grafana/Loki/Prometheus hardening; core was already live, §5 structured-metadata + Logs Drilldown deployed. |
| [`implemented/2026-06-20-unifi-declarative-config.md`](implemented/2026-06-20-unifi-declarative-config.md) | ✅ Implemented — declarative UDM config in the `homelab-iac` sister repo. |
| [`proposals/2026-06-22-declarative-implementation-plan.md`](proposals/2026-06-22-declarative-implementation-plan.md) | In progress — Spec/work-items for Harbor + k3s-mirror → declarative. |
| [`implemented/2026-06-22-harbor-declarative.md`](implemented/2026-06-22-harbor-declarative.md) | Implemented — **oneshot variant shipped, not this RFC's static stack**. |
| [`implemented/2026-06-22-harbor-pullthrough-mirror.md`](implemented/2026-06-22-harbor-pullthrough-mirror.md) | ✅ Implemented (2026-06-28) — Harbor pull-through mirror; node side live. |
| [`implemented/2026-06-24-hermes-memory-skills.md`](implemented/2026-06-24-hermes-memory-skills.md) | ✅ Implemented (record closed 2026-07-02) — §9 is the authoritative record: OCI cutover + skills `external_dirs` + SOUL `:ro` shipped; rtk thesis invalidated. Remaining items re-tracked in `hermes-deferred-improvements`. |
| [`proposals/2026-06-24-repo-structure-improvements.md`](proposals/2026-06-24-repo-structure-improvements.md) | Proposal — tighten the dendritic module structure. |
| [`proposals/2026-06-24-source-backed-host-improvements.md`](proposals/2026-06-24-source-backed-host-improvements.md) | Proposal — source-backed host security/perf/usability review. |
| [`proposals/2026-06-25-hermes-agentmemory-integration.md`](proposals/2026-06-25-hermes-agentmemory-integration.md) | Plan — **supersedes** `hermes-deferred-plans` §1. |
| [`proposals/2026-06-25-hermes-deferred-plans.md`](proposals/2026-06-25-hermes-deferred-plans.md) | Backlog — partly superseded by `hermes-agentmemory-integration`. |
| [`implemented/2026-06-26-docs-reorg-and-install.md`](implemented/2026-06-26-docs-reorg-and-install.md) | ✅ Implemented (verified 2026-07-02) — this docs layout (guides/reference/implemented/proposals), INSTALL → `guides/install.md`, `docs-check` gate in `just check`. |
| [`implemented/2026-06-26-hermes-native-llm-wiki.md`](implemented/2026-06-26-hermes-native-llm-wiki.md) | ✅ Implemented (2026-06-27; unattended cron validated 2026-06-29) — hermes-maintained Karpathy LLM wiki on the `hermes` branch (deploy key, declarative clone, wiki-curator skill, daily consolidate cron). As-built: [`hermes-llm-wiki.md`](hermes-llm-wiki.md). Follow-ups tracked in `hermes-deferred-improvements` P2–P4. |
| [`implemented/2026-06-28-cloudflare-token-terraform-migration.md`](implemented/2026-06-28-cloudflare-token-terraform-migration.md) | ✅ Implemented (2026-06-30) — Cloudflare tokens Terraform-managed in homelab-iac (least-scope, rotatable); one bootstrap token stays manual. Ph3 adopted the HA tunnel via `ignore_changes=[secret]` (write-only secret, no rotation/outage). |
| [`proposals/2026-06-29-grafana-fleet-monitoring.md`](proposals/2026-06-29-grafana-fleet-monitoring.md) | In progress — Phase 1 implemented 2026-07-01 (host-health + voyager-offsite + platform-vault + backups alert groups live); Phase 2 blocked on the cadvisor name-metric gap, Phase 3 (k3s rules) not started. |
| [`implemented/2026-06-29-repo-ssot-srp.md`](implemented/2026-06-29-repo-ssot-srp.md) | ✅ Implemented (2026-06-29) — SSOT per fact + SRP per repo across the 8-repo ecosystem. P0/P1/P2/P3/P5 (`fleet.json` topology+domains SSOT, consumers live in justfile + homelab-iac + servarr drift-check; CLAUDE.md ownership map + D1–D9 + SRP tree) + **P4** (kindle-dash → standalone OSS, `ghcr.io/erikbpf/kindle-dash` + Harbor `library` mirror, servarr pins the digest). |
| [`implemented/2026-06-29-vault-secrets-platform.md`](implemented/2026-06-29-vault-secrets-platform.md) | ✅ Implemented (P3.0–P3.2) — platform Vault as runtime-secret SSOT (docker via vault-agent, k8s via ESO, iac via provider), sops as root-of-trust/bootstrap; in-cluster Vault repositioned to discovery. P3.3 servarr→Vault in progress. |
| [`implemented/2026-06-29-opencode-improvements.md`](implemented/2026-06-29-opencode-improvements.md) | ✅ Implemented (2026-06-29) — opencode config improvements (Phases G + L1–L3 + items 2+4). |
| [`implemented/2026-06-29-vault-backup-plan.md`](implemented/2026-06-29-vault-backup-plan.md) | ✅ Implemented (gate P3.0 met 2026-06-29) — Vault backup+restore proven before any real secret: raft snapshot → restic (3 tiers incl. off-premise voyager, apart from unseal key) → textfile dead-man's-switch → Grafana/Discord; mock + fresh-cluster restore drills passed. Break-glass age key closed by crown-jewels §4b. Follow-up: schedule quarterly restore-drill. |
| [`implemented/2026-06-29-voyager-oracle-offsite-host.md`](implemented/2026-06-29-voyager-oracle-offsite-host.md) | Superseded (2026-07-01) — goal shipped (voyager off-premise restic receiver, see `offsite-dr-crown-jewels`), method did not (deployed via nixos-infect, not the disko/VM-tap path here; switch via deploy-rs). One live gap: append-only repo growth + no voyager disk alert. |
| [`implemented/2026-06-30-openbao-root-recovery.md`](implemented/2026-06-30-openbao-root-recovery.md) | ✅ Executed (2026-06-30) — recovered the lost OpenBao root token: temporarily re-enabled `generate-root` (disabled by default ≥2.5.0) via the listener, minted a new root from the unseal key, resealed sops (root + snapshot token, fixing the broken backup, + approle secret-id), sealed the kindle-dash robot secret, re-disabled. Non-destructive. |
| [`implemented/2026-06-29-codex-flake.md`](implemented/2026-06-29-codex-flake.md) | ✅ Implemented (2026-06-30) — reusable `codex-flake` Home Manager profile module for global Codex `AGENTS.md`, inline RTK guidance, caveman style, opt-in generated RTK, opt-in `config.toml`, FlakeHub publish+verify, and desktop laptop consumption. |
| [`implemented/2026-06-30-codex-flake-update-strategy.md`](implemented/2026-06-30-codex-flake-update-strategy.md) | ✅ Implemented (2026-07-01) — `codex-flake` owns an opt-in x86_64-linux fast package lane, daily updater PRs, and `codex-v*` package tags. `desktop-nixos` imports `homeManagerModules.withPackage` from the verified FlakeHub release. |
| [`implemented/2026-06-30-hermes-flake-update-hardening.md`](implemented/2026-06-30-hermes-flake-update-hardening.md) | ✅ Implemented (2026-07-01) — `hermes-flake` updater hardening: pinned actions, non-destructive rollback, state-derived tags, release-note PR context, trust-mode docs, required/advisory CI split, FlakeHub gating, and quarterly action refresh PRs. |
| [`implemented/2026-06-29-discovery-resilience-fixes.md`](implemented/2026-06-29-discovery-resilience-fixes.md) | ✅ Implemented (core, 2026-06-29) — pull-servarr reset-hard, swag-cert-monitor, AdGuard mem fix. P1-1 (compose drift) + P2 (instability root-cause) remain. |
| [`implemented/2026-06-29-session-landing-plan.md`](implemented/2026-06-29-session-landing-plan.md) | ✅ Done (2026-06-29) — landed the session's deployed/applied work onto main across all three repos. |
| [`implemented/2026-06-30-sccache-shared-cache.md`](implemented/2026-06-30-sccache-shared-cache.md) | ✅ Implemented (2026-06-30) — shared sccache WebDAV cache on orion over the tailnet for dev-loop `cargo build`; cache mode (local compile fallback), opt-in client (enabled on laptop), ACL opened fleet-wide in homelab-iac. `sccache-dist` CPU offload deferred. |
| [`implemented/2026-06-30-deploy-rs-as-deploy-standard.md`](implemented/2026-06-30-deploy-rs-as-deploy-standard.md) | ✅ Implemented (2026-06-30) — deploy-rs (magic rollback) is the fleet remote-switch standard; two-phase toolchain (install + switch). `switch-<host>`→deploy-rs (GPU hosts via `deploy-rs-boot`+reboot), `provision` for new remote hosts; nixos-anywhere/nixos-infect keep first install. Rollout: orion/discovery/kepler done, archinaut in progress, telstar pending A1 capacity. |
| [`implemented/2026-06-30-offsite-dr-crown-jewels.md`](implemented/2026-06-30-offsite-dr-crown-jewels.md) | ✅ Implemented (2026-06-30) — Oracle `voyager` is the off-premise DR anchor for the crown-jewel config tier: 4b passphrase-age escrow of the sops age key (closes the single-point-of-loss), 4a tf state → voyager append-only REST, 4c GitHub-independent `.env.sops` bundle, 4d OpenBao snapshot → voyager. Post-grill hardening §11; pending age-key rotation tracked in `reference/key-rotation.md`. |
| [`proposals/2026-07-01-opencode-flake.md`](proposals/2026-07-01-opencode-flake.md) | Ready (D1–D6 resolved 2026-07-02) — `opencode-flake`: thin profile layer wrapping upstream `programs.opencode` (dedicated `AGENTS.md` + `OPENCODE_DISABLE_CLAUDE_CODE`; G1 permissions + G3 tui in-flake, G2 providers host-local) + opt-in daily-auto-merge package lane with schema-validated config checks, Cachix, FlakeHub; laptop migrates adopt-port-delete. |
| [`proposals/2026-07-02-open-decisions-and-work.md`](proposals/2026-07-02-open-decisions-and-work.md) | Backlog — fleet-wide open decisions (A1–A12) + pending implementations (B1–B12) consolidated from the 2026-07-02 proposal audit; work items in PT-BR. |
| [`proposals/2026-07-01-telstar-oracle-arm-host.md`](proposals/2026-07-01-telstar-oracle-arm-host.md) | Ready — `telstar`, a second Oracle Always-Free VM (Ampere A1, aarch64, 2 OCPU / 12 GB) for public-facing personal projects. Fully staged (Nix host modules + Terragrunt unit + `deploy-telstar`/`switch-telstar`); **blocked only on Oracle A1 host capacity** (586 retries over 10 h + a one-shot all returned "Out of host capacity"). Deploys via nixos-anywhere + disko when a slot frees. |
| [`proposals/2026-07-02-free-tier-cloud-resources.md`](proposals/2026-07-02-free-tier-cloud-resources.md) | Proposal (skeleton, `TODO`) — verified free-tier map (Oracle, Cloudflare, Grafana Cloud, DBs, inference) onto fleet needs, reliability+privacy biased: crown-jewel legs 3/4, offsite monitoring mirror, A1 capacity ping-plan, telstar edge, AI overflow routing. 10 decision forks. |

> The original dendritic-migration design (`superpowers/specs/2026-03-18-…`) was
> **deleted** from the tree; it is recoverable from git history. The reorg
> proposal decides whether to restore it under `implemented/` or replace it with
> a short dendritic-contract note.

New design work: add an RFC under `proposals/` named
`YYYY-MM-DD-<slug>.md`; promote decisions to ADRs once locked.
