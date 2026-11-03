# Keep vs rebuild: scripts and recipes

**Status:** Research complete — feeds IP slices S2 and S4.
**Date:** 2026-11-01
**Scope:** `scripts/` (40 files) and `justfile` (374 public recipes, 8,860 lines)
at `d091d982`.

## Question

A file is cheap to delete when its knowledge can be re-derived in minutes. This
pass separates three cases that the staleness audit merged:

- **Keep** — something in the repo depends on it at runtime or it encodes a
  safety or recovery path.
- **Rebuildable** — one-off tooling whose whole content is a documented command
  or a short comparison; delete it and keep the command in the runbook.
- **Delete** — its subject is finished and no one needs the command again.

## Rules

- **RB-1 Runtime coupling.** Referenced by a Nix module, systemd unit, activation
  script, CI workflow, or retained recipe: keep.
- **RB-2 Safety gate.** Contains an authorization token, confirmation argument,
  manifest/SHA binding, hash check, or `trap` cleanup: keep. Deleting the gate
  silently weakens an operator procedure.
- **RB-3 Recovery path.** Restore, backup, drill, or incident diagnosis: keep,
  even when the phase that motivated it is closed.
- **RB-4 Credential handling.** Mints, rotates, revokes, or reads secrets: keep.
- **RB-5 Finished phase.** One-time transition for a phase declared complete:
  delete, unless RB-1 to RB-4 applies.
- **RB-6 Re-derivable one-off.** No dependency, no safety token, and the body is
  a single command or a comparison that can be retyped: delete, and record the
  command in the matching runbook or reference page.

## Scripts: 5 delete, 35 keep

| Script | Lines | Coupling | Verdict |
|---|---:|---|---|
| `scripts/archive-syncthing-conflicts.py` | 84 | guide + test | keep — recovery tool |
| `scripts/authentik-admin-token.py` | 52 | Django shell token mint | keep — RB-4 |
| `scripts/authentik-admin-token.sh` | 56 | recipe | keep — RB-4 |
| `scripts/authentik-password-hash.py` | 17 | harbor-IAM preflight test | keep — RB-4, trivially re-derivable but load-bearing for bootstrap |
| `scripts/bootstrap-authentik.sh` | 77 | recipe | keep — RB-4 |
| `scripts/builder-preflight.sh` | 46 | recipe + CI | keep — RB-1 |
| `scripts/capture-harbor-fleet-publisher-secret-id.py` | 136 | recipe + active proposal | keep — RB-4 |
| `scripts/capture-orion-display.sh` | 54 | recipe + guide | keep — RB-1 |
| `scripts/check-k3s-clock-rollout.sh` | 11 | reference doc | keep — one nix eval, cheap regression check |
| `scripts/configure-codex-ui.py` | 41 | `modules/dev/codex.nix` activation | keep — RB-1 |
| `scripts/deploy-ubuntu-work-profile.sh` | 47 | recipe | keep — user-owned work VM |
| `scripts/export-discovery-vault-contract.py` | 103 | CI test | keep — RB-1 |
| `scripts/harbor-iam-acceptance.sh` | 217 | test + active proposal | keep — RB-2 protocol |
| `scripts/harbor-iam-preflight.sh` | 152 | recipe + test | keep — RB-2 |
| `scripts/harbor-iam-provider-handoff.sh` | 77 | recipe | keep — RB-4 |
| `scripts/hermes-state-backup.sh` | 433 | deployed by `modules/hermes-checks.nix` | keep — RB-1 |
| `scripts/pr-review/apply-gate.py` | 159 | test + gate contract | keep — RB-2 |
| `scripts/pr-review/bootstrap-cron.sh` | 114 | module | keep — RB-1 |
| `scripts/pr-review/claim.py` | 54 | module | keep — RB-1 |
| `scripts/pr-review/collect.py` | 591 | module | keep — RB-1 |
| `scripts/pr-review/ledger.py` | 239 | module | keep — RB-1 |
| `scripts/pr-review/make-app-credential.sh` | 93 | none (manual) | keep — RB-4, declared manual |
| `scripts/pr-review/publish.py` | 584 | module + CI | keep — RB-1 |
| `scripts/pr-review/tokens.py` | 137 | imported by three modules | keep — RB-1 |
| `scripts/pr-review/verify-credentials.py` | 99 | none (manual) | keep — RB-4, declared manual |
| `scripts/retire-authentik-bootstrap.sh` | 70 | recipe | keep — RB-4 |
| `scripts/rotate-authentik-iac-token.sh` | 30 | recipe | keep — RB-4 |
| `scripts/sync-ubuntu-work-brave-settings.sh` | 97 | recipe | keep — user-owned work VM |
| `scripts/test_capture_orion_display.py` | 27 | CI | keep — RB-1 |
| `scripts/update-graphify-lock.py` | 76 | recipe + test | keep — RB-1 |
| `scripts/upgrade-candidate-evidence.py` | 36 | recipe + test | keep — RB-1 |
| `scripts/upgrade-hosts.nix` | 1 | recipe + test | keep — RB-1 |
| `scripts/upgrade-impact.py` | 58 | recipe | keep — RB-1 |
| `scripts/verify-ha-harbor-reader.sh` | 31 | recipe + test | keep — RB-3 |
| `scripts/verify-roaming-dns.py` | 137 | recipe + doc | keep — RB-3 |
| `scripts/p3-adguard-outage-client.sh` | 63 | deleted recipes/tests | **delete** — RB-5 |
| `scripts/p3-adguard-outage-drill.sh` | 221 | deleted recipes/tests | **delete** — RB-5 |
| `scripts/p3-adguard-outage-observe.sh` | 62 | deleted recipes/tests | **delete** — RB-5 |
| `scripts/p3-generic-dhcp-client.sh` | 67 | deleted recipe | **delete** — RB-5 |
| `scripts/p3-udhcpc-capture.sh` | 43 | deleted drill | **delete** — RB-5 |

Conclusion: scripts are not the bloat. Only the P3 drill family is removable,
and it goes because its phase is finished, not because it is cheap to rebuild.
Every other script is runtime-coupled, credential-bearing, or a recovery tool.

## Recipes: 82 delete

### Finished phases (62)

| Group | Recipes | Lines |
|---|---:|---:|
| SWAG adoption/transition (P1) | 28 | 345 |
| AdGuard transition/prefetch/split (P2) | 16 | 452 |
| Docker volume migration (P5) | 7 | 282 |
| ESP migration gates | 2 | 67 |
| Point-in-time audits | 2 | 65 |
| P3 outage drill (`p3-adguard-outage-*`, `p3-generic-dhcp-client`) | 7 | 152 |

P3 is added here for consistency: its tests and scripts are already deleted by
the plan, so its recipes cannot survive without editing them. `p3-dns-preflight`
and `p3-dns-verify` stay — `recover-kepler-dns` calls them in a live recovery
path.

### Rebuildable one-offs (20)

| Recipe | Lines | Rebuild from | Record in |
|---|---:|---|---|
| `drtest-vm-build/start/stop/wait/ssh` | 87 | `nix build .#nixosConfigurations.<host>.config.system.build.vm`, or the `sbx` package | no runbook needed; superseded |
| `voyager-vm-build/test/start/stop/smoke` | 104 | commands already listed in `docs/implemented/2026-06-29-voyager-oracle-offsite-host.md` | update that doc's recipe table |
| `prepare-kepler-fast-state`, `finalize-kepler-fast-state` | 109 | one-off migration; outcome in the Kepler reconciliation record | `docs/reference/kepler-*` |
| `kepler-retire-legacy-retrieval`, `orion-retire-legacy-llama`, `kepler-retire-ai-serving-user-approved` | 70 | retirement is done; no rerun path needed | homelab Kepler proposal |
| `p2-iac-plan-equivalence` | 183 | one-off Terraform plan comparison; P2 complete | homelab execution plan |
| `index-spark-docs`, `rebuild-docs-search` | 17 | crawl/index command; Graphify skill documents the equivalent | `docs/reference/graphify-package.md` |
| `send-discord-samples` | 37 | single `curl` to the webhook | drop |
| `grafana-alert-status` | 6 | tombstone (`exit 2`); the real command lives in `homelab-gitops` | drop |

### Thin wrappers kept

- `switch-discovery/orion/pathfinder/archinaut` — one-line `just deploy-rs`
  aliases, but they encode the per-host deploy mode and `switch-all` calls them.
- `sops`, `age-public`, `gc`, `store-repair` — one-liners around Nix commands
  that appear in operator docs; keeping them is discoverability, not logic.
- `verify-port`, `diagnose-tailscale`, `recache-orion` — single-command
  diagnostics used during incidents.

## Totals

| Measure | Before | After |
|---|---:|---:|
| Public recipes | 374 | 293 (292 plus the new `hygiene-check` guard) |
| Justfile lines | 8,860 | 6,884 |
| Scripts | 40 | 35 |
| Deleted recipes | — | 82 (1,976 lines) |

## Correction to the earlier audit

The first pass counted 54 test directories as wired because it treated any
reference as a gate. Run by an actual gate (CI or `justfile`): **40**. Another
**14** are referenced only by docs or modules (`apollo-host`,
`apollo-worklab`, `argus-security`, `dendritic-structure`, `grafana-alert-ops`,
`herdr-worklab`, `orion-main-guardrails`, `public-host-ssh`,
`servarr`, `servarr-exact-revision`, `tmux-persistence`, `tuicr`,
`wazuh-agent-canary`). **75 of 115** directories are not executed by any gate.

## Split map after these deletions

| File | Recipes | Lines |
|---|---:|---:|
| `justfile` (root: variables, exports, `default`, 3 private helpers, imports) | 4 | 25 |
| `just/discovery.just` | 41 | 1,488 |
| `just/kepler.just` | 30 | 852 |
| `just/roaming.just` | 28 | 643 |
| `just/harbor.just` | 16 | 518 |
| `just/secrets.just` | 25 | 477 |
| `just/deploy.just` | 24 | 467 |
| `just/kepler-recovery.just` | 13 | 373 |
| `just/fleet.just` | 29 | 366 |
| `just/k3s.just` | 15 | 329 |
| `just/kindle.just` | 12 | 315 |
| `just/hermes.just` | 15 | 282 |
| `just/orion.just` | 18 | 254 |
| `just/servarr.just` | 11 | 239 |
| `just/apollo.just` | 9 | 154 |
| `just/monitoring.just` | 5 | 79 |
| `just/dev.just` | 0 | 0 (all three recipes are deleted) |

`just/dev.just` disappears; `diagnose-*` fleet-wide diagnostics live in
`fleet.just`.
