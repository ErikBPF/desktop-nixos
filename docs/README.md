# docs/

Map of repo documentation. Recipes in `justfile` are the source of truth for
operations; docs explain *why* and capture designs. If a doc and a recipe
disagree, the recipe wins — flag the doc as stale.

**Status lives in the document.** Each document carries its own `**Status:**`
line. This index names purpose only, so the two cannot drift apart.

> This tree was reorganized per
> [`implemented/2026-06-26-docs-reorg-and-install.md`](implemented/2026-06-26-docs-reorg-and-install.md):
> `guides/` (install, obsidian), `reference/` (operational docs), `implemented/`
> (shipped designs), `proposals/` (active RFCs only), and a `docs-check` link
> gate wired into `just check`.

## Operational references

[Manual fork sync](guides/github-forks.md) and
[Orion display capture](guides/orion-display-capture.md) describe opt-in helpers.

[Codex tooling reconciliation](reference/codex-tooling.md) records the bounded
developer-tool changes and preserved runtime boundaries.

| Doc | Covers |
|-----|--------|
| [`reference/graphify-package.md`](reference/graphify-package.md) | Exact Graphify wheel artifacts, offline builds and explicit dependency updates. |
| [`reference/hermes-state-backup-one-pager.md`](reference/hermes-state-backup-one-pager.md) · [`behavior contract`](behaviors/hermes-state-backup.feature) | Optional encrypted two-agent backup/isolated restore helpers and retained attempt history. |
| [`reference/hermes-agent-runtime-one-pager.md`](reference/hermes-agent-runtime-one-pager.md) · [`behavior contract`](behaviors/hermes-agent-runtime.feature) | Verified image pins, Argus lifecycle/dedup and synthetic state roundtrip. |
| [`reference/hermes-agent-hardening-one-pager.md`](reference/hermes-agent-hardening-one-pager.md) · [`behavior contract`](behaviors/hermes-agent-hardening.feature) | Argus evidence/leak boundaries, terminal-only RTK rewriting, and Romozinha health/webhook scope. |
| [`reference/pr-review-ledger.md`](reference/pr-review-ledger.md) | Per-head review ledger, leases, fast collect, and worker dispatch for the Hackerman PR gate. |
| [`behaviors/orion-apollo-builders/one-pager.md`](behaviors/orion-apollo-builders/one-pager.md) | Orion/Apollo pool, bounded fallback, dedicated server enrollment and guest-only KACE. |
| [`reference/roaming-dns-probe.md`](reference/roaming-dns-probe.md) | Manual off-LAN acceptance: client routes, Discovery DNS, system resolution, and TLS-verified LiteLLM/AdGuard ingress. |
| [`behaviors/opencode-v2-migration/one-pager.md`](behaviors/opencode-v2-migration/one-pager.md) · [`session guide`](guides/opencode-v2-sessions.md) | Native two-backend V2 migration, package/plugin checks, preserved V1 state and optional context/quota trials. |
| [`behaviors/opencode-runtime-recovery/one-pager.md`](behaviors/opencode-runtime-recovery/one-pager.md) | Superseded builder recovery, Q-14 main-policy reconciliation, RTK/system HM convergence and existing sudo PATH. |
| [`behaviors/orion-main-guardrails/one-pager.md`](behaviors/orion-main-guardrails/one-pager.md) | Preserve Orion panic recovery and bounded persistent scheduled/catch-up cache builds on main. |
| [`reference/2026-10-02-cp1-clocksource-canary.md`](reference/2026-10-02-cp1-clocksource-canary.md) | Kepler guest clocksource, dependency-stop recovery, etcd failure investigation and serial worker update evidence. |
| [`behaviors/local-workspace-sessions/opencode-v2-default-one-pager.md`](behaviors/local-workspace-sessions/opencode-v2-default-one-pager.md) | OpenCode v2 as the default: packaged v2 lane in `opencode-flake`, single-config v2 plugins, `ol`/`ow` via the default alias, v1 removal. |
| [`behaviors/local-workspace-sessions/opencode-backends-one-pager.md`](behaviors/local-workspace-sessions/opencode-backends-one-pager.md) | Endeavour persistent homelab/work backends, attach commands and deployment evidence. |
| [`behaviors/opencode-three-level-backends/one-pager.md`](behaviors/opencode-three-level-backends/one-pager.md) | Three-level `pilot-l1`/`pilot-l2`/`pilot-l3` profiles on the `ol`/`ow` backends, dispatch plugin, inline config and per-backend state. |
| [`reference/2026-09-07-telemetry-drill.md`](reference/2026-09-07-telemetry-drill.md) | Bounded Discovery Alloy identity-loss procedure, rollback and live evidence; isolated Loki error handling. |
| [`reference/2026-08-30-kepler-k3s-etcd-io-incident.md`](reference/2026-08-30-kepler-k3s-etcd-io-incident.md) | Kepler k3s outage evidence, shared-pool etcd latency mechanism, safe writer capture, and storage-remediation gate. |
| [`reference/2026-08-10-endeavour-password-lockout.md`](reference/2026-08-10-endeavour-password-lockout.md) | Endeavour declarative-password lockout, recovery, root cause, and guardrails. |
| [`reference/discovery-stateful-inventory.md`](reference/discovery-stateful-inventory.md) | Time-bounded P0 owner/image/mount/volume/backup inventory for discovery state migrations. |
| [`reference/dendritic-contract.md`](reference/dendritic-contract.md) | The rules a `modules/` file must follow (registration, naming, `_` helpers). Enforced by `just structure-check`. |
| [`reference/apollo-gpu-preparation.md`](reference/apollo-gpu-preparation.md) | Open NVIDIA modules, the two RTX 5060 Ti power ceiling and arrival/acceptance gates. |
| [`reference/apollo-nic-recovery.md`](reference/apollo-nic-recovery.md) | Permanent-MAC uplink naming, DHCP/NAT recovery and reboot acceptance. |
| [`reference/kepler-apollo-gpu-exchange.md`](reference/kepler-apollo-gpu-exchange.md) | GPU exchange, bounded CUDA correctness check and household inference suspension. |
| [`reference/kepler-ai-serving.md`](reference/kepler-ai-serving.md) | Retired Kepler AI-serving topology, retained as historical routing and model context. |
| [`reference/kepler-zfs-setup.md`](reference/kepler-zfs-setup.md) | Imperative ZFS pool creation on kepler (pools are *not* in disko). Needed when reprovisioning or adding bulk-pool. |
| [`reference/kepler-k3s-platform-status.md`](reference/kepler-k3s-platform-status.md) | As-built status of the kepler k3s cluster + `homelab-gitops` workloads: topology, what's implemented/validated, next steps, cluster gotchas. |
| [`reference/harbor-discovery-registry.md`](reference/harbor-discovery-registry.md) | Harbor registry on discovery — the imperative baseline. |
| [`reference/2026-10-13-ha-publisher-bootstrap.md`](reference/2026-10-13-ha-publisher-bootstrap.md) | Controller-only IaC Harbor publisher SecretID capture; target preflight, shared lock, no inherited proxy. |
| [`reference/2026-09-07-desktop-reconciliation.md`](reference/2026-09-07-desktop-reconciliation.md) | Historical rollout, ten-stash review and key-rotation correction. |
| [`reference/opencode-profiles.md`](reference/opencode-profiles.md) | Declarative V2 config, explicit native workspace backends, private separate state, three-level agents, plugins and activation boundaries. |
| [`reference/openbao-hardening.md`](reference/openbao-hardening.md) | Preserve tailnet ingress identity; private declarative audit and controlled restart gates. |
| [`reference/vault-disaster-recovery.md`](reference/vault-disaster-recovery.md) | OpenBao DR runbook — sealed/corrupt/total-loss recovery; the fresh-cluster restore (unseal with the OLD sops key) tested 2026-06-29. |
| [`reference/key-rotation.md`](reference/key-rotation.md) | When (and when not) to rotate each fleet key/secret + how — trigger-driven, weighted by blast radius; the age key, escrow passphrase, voyager REST creds, restic/OpenBao keys. |
| [`reference/voyager-offsite-maintenance.md`](reference/voyager-offsite-maintenance.md) | Voyager append-only restic tier: what lives there, monitoring/alerts, weekly `restic check`, manual prune window, owed restore drill. |
| [`reference/service-exposure.md`](reference/service-exposure.md) | Discovery exposure audit: what's LAN/tailnet/internet-reachable and why — Docker-published ports bypass the NixOS firewall. Re-audit with `just verify-firewall`. |
| [`reference/recovery-frozen-pid1.md`](reference/recovery-frozen-pid1.md) | Emergency tape: a systemd-bumping `switch` froze PID1 (net dead, `sudo reboot` hangs) → SysRq S+U+B, else force power-off is safe (btrfs/LUKS is CoW-clean, 0 corruption verified 2026-07-12). Fleet-upgrade-hardening P6. |
| [`guides/break-glass.md`](guides/break-glass.md) | Value-free incident decision tree for deploy, Servarr, SecretSpec, Vault Agent, OpenBao, DNS, PID1, and credential recovery. |
| [`guides/obsidian.md`](guides/obsidian.md) | Obsidian + sync configuration for the desktop hosts. |
| [`guides/install.md`](guides/install.md) | Host bootstrap walkthrough (nixos-anywhere / ISO paths). |
| [`guides/yazi.md`](guides/yazi.md) | Nautilus/Yazi desktop workflow: launch shortcuts, GUI→Yazi keymap bridge, and path persistence. |
| [`guides/apollo-repository-sync.md`](guides/apollo-repository-sync.md) | Selected Documents repo sync with Orion; guarded initial join. |
| [`guides/syncthing-conflict-recovery.md`](guides/syncthing-conflict-recovery.md) | Verified conflict archives, Git preservation and runtime scope. |
| [`guides/umbrella-sessions.md`](guides/umbrella-sessions.md) | `l1/l2` on Orion; `w1/w2` on Apollo. |
| [`guides/orion-retirement-staging.md`](guides/orion-retirement-staging.md) | Encrypted Kepler archives, checksums and Gemini retirement. |
| [`guides/orion-repository-storage.md`](guides/orion-repository-storage.md) | Selected personal repositories on projects disk; stable umbrella paths. |
| [`guides/orion-storage-cutover.md`](guides/orion-storage-cutover.md) | Existing-disk separation and completed guarded cleanup. |

## Designs and proposals

| Doc | Purpose |
|-----|---------|
| [`proposals/2026-10-31-repository-simplification.md`](proposals/2026-10-31-repository-simplification.md) · [`behavior contract`](behaviors/repository-simplification/repository-simplification.feature) | Deletion manifest and delivery record for finished-migration tooling, unwired tests, pointer stubs, and the Discovery stateful-stack helpers. |
| [`proposals/2026-11-13-opencode-shell-permissions.md`](proposals/2026-11-13-opencode-shell-permissions.md) | Effective OpenCode shell policy: explicit `shell allow *`, removed patch and history denials, architect inherits the global rules, preserved secret, blob-read and cross-host deploy denials. |
| [`proposals/2026-09-08-fleet-capability-composition.md`](proposals/2026-09-08-fleet-capability-composition.md) · [`behavior contract`](behaviors/fleet-capability-composition/composition.feature) | grounded `/pl` and `/ip` draft for shared wake/routing capabilities, developer-tool composition and import-only profiles; no implementation or deployment. |
| [`Independent local workspace sessions`](proposals/2026-09-12-local-workspace-sessions.md) | preserves the recorded September 12 activation; isolated publication checks validate the corrected independent-session behavior. |
| [`proposals/2026-08-24-kepler-cold-restart-resilience.md`](proposals/2026-08-24-kepler-cold-restart-resilience.md) · [`behavior contract`](behaviors/kepler-cold-restart/kepler-cold-restart.feature) | Implementation planned — reviewed `/pl` contract and `/ip` slices define a forced-off, two-minute-off, power-on sequence, exact storage/source gates, and a 10-minute return deadline. |
| [`behaviors/sbx/behavior.md`](behaviors/sbx/behavior.md) · [`behavior contract`](behaviors/sbx/sbx.feature) | package-local unfree allowance, corrected Docker release source, real build, and CLI smoke gate pass. |
| [`behaviors/deepseek-tmux-workspaces/deepseek-tmux-workspaces.feature`](behaviors/deepseek-tmux-workspaces/deepseek-tmux-workspaces.feature) | eight persistent, single-writer DeepSeek Harness slots per checkout; implementation is planned in the [canonical homelab proposal](https://github.com/ErikBPF/homelab/blob/main/docs/proposals/2026-08-24-deepseek-harness-remote-workspaces.md). |
| [`behaviors/discovery-secondary-dns/behavior.md`](behaviors/discovery-secondary-dns/behavior.md) · [`test contract`](behaviors/discovery-secondary-dns/test-contract.md) | Kepler LAN secondary resolver, Vanguard tailnet resolver, narrow DHCP ownership, and the P3 outage proof. |
| [`behaviors/discovery-adguard-adoption/behavior.md`](behaviors/discovery-adguard-adoption/behavior.md) · [`test contract`](behaviors/discovery-adguard-adoption/test-contract.md) | Fixtures and value-free read-only preflight for the P2 AdGuard in-place adoption. |
| [`behaviors/kepler-collision-migration/behavior.md`](behaviors/kepler-collision-migration/behavior.md) · [`test contract`](behaviors/kepler-collision-migration/test-contract.md) | Approved normative K0–K5 recovery contract — recovery completed with the execution plan's recorded operator-approved retirement deviation. |
| [`behaviors/openbao-audit-rotation/behavior.md`](behaviors/openbao-audit-rotation/behavior.md) | service-owned audit rotation and guarded empty-file recovery; deployment verification pending. |
| [`behaviors/update-safe/behavior.md`](behaviors/update-safe/behavior.md) | staged/unstaged lock guard and exact-byte failure/interrupt rollback; command tests pass, merge pending. |

Shipped designs live in [`implemented/`](implemented/); each document carries its own
`**Status:**` line. Proposals whose canonical copy moved to `homelab` are linked
from the [homelab proposal index](https://github.com/ErikBPF/homelab/blob/main/docs/proposal-index.md).

> The original dendritic-migration design (`superpowers/specs/2026-03-18-…`) was
> **deleted** from the tree; it is recoverable from git history. The reorg
> proposal decides whether to restore it under `implemented/` or replace it with
> a short dendritic-contract note.

New design work: add an RFC under `proposals/` named
`YYYY-MM-DD-<slug>.md`; promote decisions to ADRs once locked.
