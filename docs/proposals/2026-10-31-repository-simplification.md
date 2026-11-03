# Repository simplification: desktop-nixos

**Status:** Implemented on the task branch — pending review and publication.
**Date:** 2026-10-31
**Scope:** `desktop-nixos` tracked content. No intended host behavior change.
**Behavior contract:** [`behaviors/repository-simplification/repository-simplification.feature`](../behaviors/repository-simplification/repository-simplification.feature)
**Keep/rebuild research:** [`behaviors/repository-simplification/keep-vs-rebuild.md`](../behaviors/repository-simplification/keep-vs-rebuild.md)
**Stage page:** [`behaviors/repository-simplification/one-pager.md`](../behaviors/repository-simplification/one-pager.md)

## Seed (verbatim)

> our desktop-nixos repo is too encumbered with one-off tests, unnecessary just
> comnands and a lot of situational files. Lets do a /pl /ip and /rv plan of
> overall simplification. Lets look for stale code, for duplicated info and for
> deletable itens

## Outcome

The repository keeps one executable path per live operation, one canonical copy
per document, and no test that no gate runs. Finished migrations keep their
acceptance evidence and a single runbook, not their transition tooling.

## Motivation

The repo is the fleet's control plane, but most of its mass is archaeology.
A command that performed a completed migration competes for attention with the
commands that run the fleet today, and an unwired test reads as coverage while
providing none.

Three costs are observable:

1. **Navigation cost.** `just --list` prints 374 recipes; 25% of the justfile is
   one migration programme. Operators scan past history to find `deploy-rs`.
2. **False coverage.** 61 of 115 test directories are referenced by no CI job,
   justfile recipe, module, or script.
3. **Drift.** `docs/README.md` restates every document's status. It already
   contradicts the canonical record: it still marks the stateful-stack phases as
   pre-P2 and the Discovery ESP migration as unapproved, while the owning plan
   records P1–P6 as complete and the ESP work as implemented.

## Measured baseline

Revision `d091d982` (main), 2026-10-31.

| Surface | Measurement |
|---|---|
| Tracked files | 873 — `modules/` 416, `tests/` 198, `docs/` 172, `scripts/` 40 |
| `justfile` | 8,860 lines, 374 recipes, 425 KB |
| `discovery-*` recipes | 80 recipes, 2,214 lines (25.0%) |
| `verify-*` / `diagnose-*` | 30 / 22 recipes, 987 lines |
| Test directories | 115; **40 run by a gate** (38 CI directories + one file target, 2 justfile); 14 referenced only by docs or modules; 61 referenced nowhere |
| Test tree | 2.1 MB |
| Docs | 171 files, 1.6 MB; 22 are `# Moved` pointer stubs; README 36 KB |
| Migration helpers in `modules/` | 15 `_stateful-*` files, 234 KB, plus `stateful-stack-ops.nix` |
| Registered flake modules | 199; 0 registered names are unreferenced elsewhere |
| Rebuildable one-offs | 20 recipes, 613 lines, no gate and no safety token |
| Unreferenced asset | `config/themes/wallpapers/wallpaper_old.png`, 819,500 B, 0 references |
| Git state | 55 worktrees, 87 local branches, 15 merged, 4 dirty |

Commands used: `just --list --unsorted`, `wc -l justfile`, `git ls-files`,
`git grep -l -F "tests/<dir>" -- . ':!tests'`, `git worktree list`,
`du -cb`, and the recipe-spanning script recorded in the discovery receipt.

## Evidence that the migration tooling is finished

`homelab/docs/proposals/2026-07-13-stateful-stack-release-hardening-execution-plan.md`
states at lines 3–6 that P0, Kepler recovery, Discovery P1 SWAG adoption, P2
AdGuard in-place adoption, P3 secondary-DNS outage proof, P4 AdGuard Terraform
ownership, P5 canonical-volume migration, and P6 kindle-dash releases are
complete, and that P7 is active. `homelab/docs/proposal-index.md` records the
fleet ESP enlargement and Discovery ESP migration as implemented.

No sibling repository invokes the tooling: `git grep` over `homelab-iac`,
`homelab-gitops`, `servarr`, `aster`, `cognee-homelab`, and `ndc` finds no
reference to `stateful-stack-ops`, `discovery-swag-transition`,
`discovery-adguard-transition`, or `p3-adguard`. The only external reference is
the homelab proposal document itself.

## Accepted decisions

| ID | Decision | Consequence |
|---|---|---|
| D-1 | Delete finished-migration tooling and keep one runbook | Recipes, transition tests, scripts, and `_stateful-*` helpers leave the repo; the homelab plan records the retirement and retains outcome/rollback prose. |
| D-2 | Triage unwired tests: delete dead, bind live | A retained test must name a path that still exists and be referenced by a gate in the same change. |
| D-3 | Split the justfile by domain | The user asked for separate justfiles. The split lands as its own slice after deletion, using `import` (not `mod`) so every invocation keeps its current spelling. |

## Decision rules

- **R1 — Finished phase.** A recipe is removable when its phase is declared
  complete in the owning contract and its body performs a one-time transition,
  adoption, inventory, or rollback for that phase.
- **R2 — Capability, not phase.** Restore drills, backups, live diagnostics, and
  anything whose owning phase is still active stay, regardless of prefix.
- **R3 — Test rule.** A test remains only if it asserts a live declared path and
  is added to a gate in this change. Otherwise it is deleted with its subject.
- **R4 — One canonical record.** A local document that only points at the
  homelab record is deleted; the README row links the canonical URL directly.
- **R5 — Status lives once.** A document's `**Status:**` line is authoritative.
  The README index describes purpose and never restates status.
- **R6 — Receipts survive.** `.feature` contracts, acceptance evidence, and RV
  reports are records, not situational files. They are not deleted by this work.

## Deletion manifest

The per-file keep/rebuild evidence is in the
[keep-vs-rebuild audit](../behaviors/repository-simplification/keep-vs-rebuild.md).

### M1 — justfile: finished migration transitions

Delete 55 recipes:

- 28 `discovery-swag-*` adoption/transition/resume/finalize/amendment/rollback
  recipes (P1 complete). Retain `discovery-swag-restore-drill`.
- 16 `discovery-adguard-*` transition/inventory/prefetch/split recipes (P2
  complete). Retain the four `restore-*` recipes and
  `discovery-adguard-exporter-diagnostic`.
- 7 `discovery-docker-*` mirror/scratch recipes (P5 complete).
- 2 `discovery-esp-*` migration gates (ESP implemented).
- 2 point-in-time audits: `discovery-migration-inventory`,
  `discovery-telstar-state-inventory`.

The 55 bodies total 1,211 lines.

Also delete the now-unused recipe-private helpers in the same file until
`just --list` contains no recipe whose body references a deleted script.

### M1b — justfile: P3 outage drill

Delete 7 recipes with the P3 scripts and tests they call:
`p3-generic-dhcp-client`, `p3-adguard-outage-{prepare,plan,observe,execute,cleanup}`,
`p3-adguard-observation-recover` (152 lines). Retain `p3-dns-preflight` and
`p3-dns-verify`, which `recover-kepler-dns` calls.

### M1c — justfile: rebuildable one-offs

Delete 20 recipes (613 lines) whose knowledge is one command or one completed
comparison: `drtest-vm-*` (5), `voyager-vm-*` (5), `prepare/finalize-kepler-fast-state`,
`kepler-retire-legacy-retrieval`, `orion-retire-legacy-llama`,
`kepler-retire-ai-serving-user-approved`, `p2-iac-plan-equivalence`,
`index-spark-docs`, `rebuild-docs-search`, `send-discord-samples`, and the
`grafana-alert-status` tombstone. Commands move to the named runbook or the
referencing doc.

M1, M1b, and M1c remove 82 recipes and 1,976 lines. The file lands at 292
public recipes and 6,884 lines before the split.

### M2 — tests: ungated directories

No gate ran 75 of the 115 directories: 61 had no reference at all, and 14 were
referenced only by docs or modules. The delivery deletes 10 and gives every
survivor a gate or a manual row:

- Deleted with their subject: the 7 migration suites (`p1-swag-preflight`,
  `p1-swag-transition`, `p1-swag-transition-amendment`, `p2-adguard-preflight`,
  `p3-adguard-outage`, `p3-generic-dhcp-client`,
  `discovery-esp-scratch-restore`), `orion-owner-cutover`, and the 2 static
  suites whose assertions name moved configuration (`kepler-crash-monitoring`,
  `postgres-exporter-firewall`).
- Reduced rather than deleted: `orchestration` keeps its unit-lifecycle test,
  `kepler-fast-state` keeps its microvm-layout and resize tests, and
  `dead-mans-switch` keeps the probe-procedure test. Only assertions whose
  subject was deleted are removed.
- 35 static suites are bound to the `Static contracts and repository hygiene`
  CI step.
- 32 runtime suites are declared in `tests/MANUAL.md` with command and
  prerequisite.

### M2b — justfile split by domain

After M1–M1c, move recipe bodies into fifteen imported files without editing
them:

`just/fleet.just`, `just/deploy.just`, `just/secrets.just`,
`just/discovery.just`, `just/kepler.just`, `just/kepler-recovery.just`,
`just/orion.just`, `just/roaming.just`, `just/apollo.just`, `just/harbor.just`,
`just/k3s.just`, `just/hermes.just`, `just/kindle.just`, `just/servarr.just`,
`just/monitoring.just`.

The root `justfile` keeps all variables and `export` lines, `default`, and the
private helpers `_builders`, `_host-ip`, `_host-guard`, then imports the files.
Use `import`, not `mod`: `mod` would rename every recipe to `just <file> <recipe>`.
Per-file counts are in the [split map](../behaviors/repository-simplification/keep-vs-rebuild.md#split-map-after-these-deletions).

### M3 — docs: pointer stubs and status duplication

- Delete 22 `# Moved` stubs (18 under `docs/proposals/`, 4 under
  `docs/implemented/`).
- Replace each affected README row with a direct link to the canonical homelab
  URL.
- Rewrite `docs/README.md`: doc, one-line purpose, no status restatement. Target
  under 20 KB (from 36 KB).
- Retain all `.feature` files, one-pagers, and evidence documents (R6).

### M4 — scripts

Delete `scripts/p3-adguard-outage-client.sh`, `p3-adguard-outage-drill.sh`,
`p3-adguard-outage-observe.sh`, `p3-generic-dhcp-client.sh`, and
`p3-udhcpc-capture.sh` (51,748 B) with their recipes and tests.

### M5 — modules: Discovery stateful-stack ops

Delete `modules/hosts/discovery/stateful-stack-ops.nix` and the 15
`modules/hosts/discovery/_stateful-*` helpers (234,150 B).

This removes Discovery system packages (`discovery-stateful-stack-ops`,
`discovery-stateful-swag-*`, `discovery-stateful-adguard-*`), the never-enabled
`discovery-stateful-stack-fixture` unit, and the
`/var/lib/stateful-stack-migrations` tmpfiles entries. Retained evidence on disk
is unaffected. Verified: no sibling repository and no retained recipe calls
these packages.

### M5b — modules: throwaway deploy-rs VM

Delete `modules/hosts/drtest/` and the `drtest` node in `modules/deploy-rs.nix`.
The VM proved deploy-rs magic rollback for the 2026-06-30 standard, which is now
the deployed default. Its lifecycle recipes were removed with M1c, so leaving
the composition would have left a VM with no interface.

### M6 — assets

Delete `config/themes/wallpapers/wallpaper_old.png` (819,500 B, 0 references).
Keep `.secretsignore` unless the security scanner is confirmed not to read it by
convention.

### M7 — git state (follow-up, not this change)

55 worktrees, 87 local branches, 15 merged. Cleanup requires inspecting each
dirty worktree (4 present) and unmerged commits; it runs as a separate,
explicitly authorized step with `git worktree remove`.

## Keep boundaries

- Every `*-restore-*`, `*-drill`, `*-backup*` recipe and its script/support file.
- The Kepler recovery and collision surface (`kepler-recovery-*`,
  `_collision_recovery_*`), governed by the active
  `2026-08-24-kepler-cold-restart-resilience.md` proposal.
- Live diagnostics: `discovery-apparmor-diagnostic`,
  `discovery-openbao-access-diagnostic`, `discovery-activation-diagnostic`,
  `discovery-servarr-*`, `harbor-iam-*`.
- Fleet, deploy, secrets, and host lifecycle recipes.

## Decision map

| Node | State | Basis |
|---|---|---|
| M1 scope | Settled | Phase status in the homelab execution plan; no consumers. |
| M2 per-test verdicts | Open — IP | Requires a path-existence and gate check per directory. |
| M5 host impact | Settled by eval | Removing the module and its `default.nix` import changes Discovery's toplevel; `just dry discovery` proves eval. |
| M7 worktree cleanup | Deferred | Needs inspection of 4 dirty worktrees and 72 unmerged branches. |
| Justfile split | Settled | 15 imported files by domain; `import` preserves `just <recipe>` names. |
| README status column | Settled (R5) | Drift demonstrated by ESP and P2/P3 rows. |

## Non-goals

- Changing host behavior, module composition, or fleet topology.
- Rewriting or deleting acceptance evidence, `.feature` contracts, or one-pagers.
- Deduplicating the `codex`/`opencode` Graphify skill trees (they differ
  intentionally in two files; low value).
- Deleting the work VM, Hermes, Harbor, or DR tooling.
- Reorganizing `modules/` beyond removing the files listed above.

## Verification

1. `just --list` still lists every retained capability; no deleted name is
   referenced by a remaining recipe or script (`git grep`).
2. `just lint`, `just fmt-check`, `just docs-check`, `just structure-check`.
3. `just dry discovery` (touched host) and `just dry-all` for the full fleet.
4. CI green, including the new static-contract job if M2 adds one.
5. `just check` on the merge candidate.

## Rollback

Every deletion is a tracked-file removal on one branch. Revert the merge commit
to restore the previous state; no host was switched, so no runtime rollback is
needed. Discovery's toplevel changes only when the deletion is deployed, and the
removed packages are not referenced by any retained service.

## Open questions

- Q-1: Does the security scanner read `.secretsignore` by convention? If not,
  delete it in M6.
- Q-2: Should the M2 static-contract job run the whole retained set on every PR,
  or on a nightly schedule? Default: every PR, because the set is static and
  cheap.
