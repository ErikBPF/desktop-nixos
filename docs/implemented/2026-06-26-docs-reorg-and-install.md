---
title: Docs reorganization + INSTALL relocation and refresh
status: Implemented (verified 2026-07-02) — all five phases executed. guides/ + reference/ + implemented/ + proposals/ layout live, INSTALL relocated to guides/install.md, docs-check wired into just check, README index regenerated with fact-based statuses. The §11 open question (restore old dendritic design vs write a contract) was resolved by the repo-structure proposal choosing docs/reference/dendritic-contract.md.
date: 2026-06-26
audience: Maintainers of desktop-nixos
post-read-action: Approve the target docs layout and the INSTALL.md update scope, then execute the phases in order.
---

# Docs reorganization + INSTALL relocation and refresh

## 1. Summary

`docs/` started as a flat folder with an index plus a growing `proposals/`
pile. It has drifted: the index links a file that no longer exists, eight
proposals are missing from the index, implemented designs sit next to live
RFCs with no status signal, and the install guide lives at the repo root
(`INSTALL.md`) instead of inside `docs/`.

This proposal does two things:

1. **Relocate and refresh `INSTALL.md`** — move it into `docs/`, update it to
   match the current fleet, fold in the repo-hygiene rules, and refresh the
   sops/secrets flow.
2. **Reorganize `docs/` into a typed taxonomy** — guides, reference, ADRs
   (locked decisions), and active proposals — with a status convention and a
   regenerated index.

This is documentation-only. No host behavior changes. It complements, and does
not replace, [`2026-06-24-repo-structure-improvements.md`](../proposals/2026-06-24-repo-structure-improvements.md)
(that proposal's Phase 6 "Refresh docs" is the seed for this one).

## 2. Current state (findings)

```text
repo-root/
  INSTALL.md            ← install guide lives OUTSIDE docs/
  README.md             ← no docs links
docs/
  README.md             ← index (stale, see below)
  OBSIDIAN_SETUP.md
  harbor-discovery-registry.md
  kepler-ai-serving.md
  kepler-k3s-platform-status.md
  kepler-zfs-setup.md
  proposals/            ← 18 files, mixed statuses, flat
```

Concrete problems:

- **Dead link in the index.** `docs/README.md:21` links
  `superpowers/specs/2026-03-18-dendritic-migration-design.md`. That file (and
  the `superpowers/` tree) was deleted; the link is broken.
- **Index is incomplete.** It lists ~10 of 18 proposals. Missing:
  `2026-06-19-kepler-k3s-microvm-cluster`, `2026-06-20-archinaut-kernel-direct-boot`,
  `2026-06-20-lazy-trees-determinate-nix`, `2026-06-22-declarative-implementation-plan`,
  `2026-06-22-harbor-declarative`, `2026-06-22-harbor-pullthrough-mirror`,
  `2026-06-24-hermes-memory-skills`, `2026-06-25-hermes-agentmemory-integration`,
  `2026-06-25-hermes-deferred-plans`.
- **Status exists in-file but not in the index.** 17 of 19 design docs already
  declare a `**Status:**` line; the two without one are
  `2026-06-22-declarative-implementation-plan.md` and
  `archinaut-migration-plan.md`. The defect is that the index does not surface
  those statuses and that implemented designs share the `proposals/` folder
  with never-started skeletons — not that the docs lack status.
- **`INSTALL.md` is at the root** and is stale (see §4): the hosts table omits
  `archinaut`, and the just-command reference is out of date.
- **No ADR location.** The global workflow is RFC → ADR → Spec, but there is no
  `docs/` home for locked decisions, so implemented RFCs never graduate.

## 3. Goals / non-goals

**Goals**

- **Fact-based docs.** Every status reflects verified repo/deployment reality,
  not aspiration or inference. A doc that claims *Implemented* must name the
  shipped artifact (host, repo, service); if it cannot, it is not implemented.
  This is the through-line of the whole proposal — the v1 triage table was
  wrong precisely because it inferred instead of reading the files.
- One predictable place per document type.
- Status surfaced in the index; finished designs graduate to `implemented/` or
  are deleted — never archived in a graveyard.
- `INSTALL.md` inside `docs/`, current, and linked correctly.
- An index kept accurate by a check (`docs-check`), not by discipline alone.
- Git history preserved across moves (`git mv`).

**Non-goals**

- No changes to `modules/` layout — that is the separate repo-structure
  proposal.
- No rewriting of proposal *content*, only relocation + status tagging.
- No new planning tooling beyond a cheap link/index check.

## 4. INSTALL.md update scope

Selected scope: **fleet reality + repo-hygiene rules + sops/secrets flow.**

### 4.1 Current fleet reality

- **Add `archinaut` to the hosts table.** It is a deployed fleet host (RPi 3
  Model B+, BIQU B1 Klipper, WiFi, `192.168.10.225`, kernel-direct boot,
  services-only). Currently absent.

  | Host | Type | Hardware | IP |
  |------|------|----------|----|
  | archinaut | Printer (RPi 3B+) | BCM2837, Klipper/Moonraker/Mainsail, WiFi | 192.168.10.225 |

- **Refresh the "Just Commands Reference."** It omits the per-host deploy
  recipes (`deploy-orion`, `switch-orion`, `deploy-kepler`, `switch-kepler`,
  any archinaut recipe) and the sister-repo sync recipes (`sync-servarr`,
  `push-env`, `sync-stack`). *Recommendation:* stop hand-maintaining the full
  list — keep a short "run `just` to list all recipes" pointer plus the
  five-or-six most common, so it cannot drift again.
- **Auto-update section:** confirm `archinaut` participates (or note that it
  does not), and cross-link the kepler generation-cap constraint (small ESP →
  cap generations at 2) so a reader hits it before a failed activation.

### 4.2 Repo-hygiene rules

The authoritative rules already live in `CLAUDE.md` (Defensive Commit Rules,
repo-specific never-commit patterns). To avoid two sources of truth, INSTALL
should **link** to those, plus add a short, install-specific "local junk"
note that is genuinely new:

- Gitignored, regenerated-on-demand, safe to delete: `.direnv/`, `.ruff_cache/`,
  `result` / `result-*` symlinks, agent runtime state (`.ralph/`, `.bg-shell/`,
  `_bmad-output/`, `logs/`).
- `ampagent-*.deb` at the root is **local-only and token-bearing** — the source
  `just add-ampagent` imports into the nix store. Do not commit it; do not
  delete the only copy unless it is already in the store.
- `.gitignore` now also covers `.ruff_cache/ .mypy_cache/ .pytest_cache/`
  (added during the cleanup that motivated this proposal).

> Judgment call for the human: duplicate the never-commit list into INSTALL, or
> link to `CLAUDE.md`? Recommendation: link, to keep one source of truth.

### 4.3 sops / secrets flow

- Re-verify the four age-key paths (A automatic / B USB / C scp / D generate)
  against the current `just bootstrap` and `just nixos-anywhere` recipes.
- Cross-reference `.sops.yaml`, `just sops`, `just rsync-sops`, `just age-*`.
- Restate the repo rule: secrets are **sops-encrypted only**; no plaintext
  credentials ever land in the repo.
- Confirm the ISO bootstrap password reference is still correct (or move it to
  a placeholder if it has changed).

## 5. Proposed target layout (Heavy)

```text
docs/
  README.md                      # index, regenerated; status legend at top

  guides/                        # how-to walkthroughs
    install.md                   # ← moved from /INSTALL.md, refreshed (§4)
    obsidian.md                  # ← OBSIDIAN_SETUP.md

  reference/                     # operational "why" — as-built OR prepared
    kepler-ai-serving.md
    kepler-zfs-setup.md
    kepler-k3s-platform-status.md
    harbor-discovery-registry.md        # NB: "prepared, not yet deployed"

  implemented/                   # shipped designs, kept as the record
    dendritic-module-layout.md          # from the deleted superpowers design
    unifi-declarative-config.md
    archinaut-printer-host.md
    archinaut-kernel-direct-boot.md
    harbor-declarative.md               # NB: shipped the oneshot variant
    ...                          # see triage table §6

  proposals/                     # ACTIVE RFCs only (date-slug names)
    2026-06-24-repo-structure-improvements.md
    2026-06-26-docs-reorg-and-install.md   # this file
    ...
```

**No `done/` archive.** A finished design either graduates to `implemented/`
(it documents what shipped and stays useful) or is **deleted** (pure execution
checklists and superseded plans — git history is the archive). `proposals/`
holds only open work; nothing dead-ends in a graveyard folder.

Rationale: type-first folders answer "where does X go?" without judgment.
`implemented/` gives shipped designs a home, which is what keeps `proposals/`
honest — it should contain only things still open.

> **Folder choice (was an error in v1):** these are full implemented *RFCs*,
> not short context/decision/consequence *ADRs*. Moving them as-is into an
> `architecture/`/`adr/` tree and renumbering them would mislabel them. Two
> honest options: (a) `implemented/` — move as-is, zero rewrite (recommended);
> or (b) actually distill one-page ADRs from each — real, unbudgeted writing
> work. `reference/` holds operational "why" docs regardless of deploy state,
> so a "prepared, not yet deployed" doc still belongs there.

## 6. Proposal triage

Bucketing of the current 19 docs. **Status column is each file's own declared
`**Status:**` line** (read 2026-06-26), not inference — so the move targets are
firm except the two files that declare nothing (flagged "no status line").

| File | Proposed bucket | Declared status |
|------|-----------------|-----------------|
| superpowers `2026-03-18-dendritic-migration-design` | implemented (or short contract) | Was implemented; file deleted — restore from git or rewrite |
| `2026-06-20-unifi-declarative-config` | implemented | **IMPLEMENTED** |
| `2026-06-16-printer-nixos-host` | implemented | ✅ IMPLEMENTED (2026-06-21) |
| `2026-06-20-archinaut-kernel-direct-boot` | implemented | ✅ IMPLEMENTED (2026-06-21) |
| `2026-06-22-harbor-declarative` | implemented | Implemented — **oneshot variant ≠ this RFC's static stack** |
| `archinaut-migration-plan` | **delete** | **no status line** — execution checklist, archinaut done; git history is the archive |
| `2026-05-23-home-assistant-declarative` | proposals | Proposal |
| `2026-05-27-home-assistant-voice-assistant` | proposals | Proposal |
| `2026-06-20-cluster-homelab-gitops` | proposals | Proposal (skeleton, TODO) |
| `2026-06-20-telemetry-hardening` | proposals | Proposal (skeleton, TODO) |
| `2026-06-19-kepler-k3s-microvm-cluster` | proposals | Proposal (grilled twice) |
| `2026-06-20-lazy-trees-determinate-nix` | proposals | Plan (skeleton, TODO) |
| `2026-06-22-declarative-implementation-plan` | proposals | **no status line** — add one |
| `2026-06-22-harbor-pullthrough-mirror` | proposals | Proposal (scoped, not applied) |
| `2026-06-24-repo-structure-improvements` | proposals | Proposal |
| `2026-06-24-source-backed-host-improvements` | proposals | Proposal |
| `2026-06-24-hermes-memory-skills` | proposals | **Partially implemented** (§9 authoritative) |
| `2026-06-25-hermes-agentmemory-integration` | proposals | Plan — **supersedes** deferred-plans §1 |
| `2026-06-25-hermes-deferred-plans` | proposals | Backlog — **partly superseded** by agentmemory-integration |

**Supersession edges the index must preserve** (a flat move loses them):

- `hermes-agentmemory-integration` → supersedes → `hermes-deferred-plans` §1.
- `harbor-declarative` documents a static stack but the **oneshot variant
  shipped** — the doc ≠ the deployed design; note this where it lands.

`harbor-discovery-registry.md` goes to `reference/` but its status is
**"prepared, not yet deployed"** — `reference/` holds operational "why"
regardless of deploy state, so this is fine; do not imply it is as-built.

## 7. Conventions (new)

- **Status already exists in-body** on 17/19 docs — the work is to (a) surface
  it in the index and (b) add a `**Status:**` line to the two that lack one
  (`declarative-implementation-plan`, `archinaut-migration-plan`). Optionally
  normalize the existing free-text statuses to a fixed set
  `Proposal | In progress | Implemented | Superseded | Backlog`. Do **not**
  rewrite the 17 that already declare status.
- **Proposals** keep `YYYY-MM-DD-<slug>.md` names.
- **ADRs** use a sequential `NNNN-<slug>.md` name and never change number once
  assigned.
- **README index** carries a one-line status legend and one row per doc. Add a
  `just docs-check` (report-only) that flags `docs/` markdown links with no
  target — this is what prevents the dead-link drift that triggered this
  proposal. Not free: it needs a small script (grep relative links → `test -e`)
  or a linkcheck binary; it is **Phase 2** — built before any moves, not a
  freebie bolted on at the end.

## 8. Inbound references to fix on move

Every move must update these (found by grep — this is the complete list today):

| Mover | Referenced by | Line | New target |
|-------|---------------|------|-----------|
| `INSTALL.md` → `docs/guides/install.md` | `docs/README.md` | 15 | `guides/install.md` |
| superpowers design (deleted) | `docs/README.md` | 21 | `implemented/dendritic-module-layout.md` or remove |
| `docs/kepler-zfs-setup.md` → `docs/reference/` | `INSTALL.md` | 127, 145 | `../reference/kepler-zfs-setup.md` |
| `docs/kepler-zfs-setup.md` → `docs/reference/` | `modules/hosts/kepler/hardware.nix` | 40 | `docs/reference/kepler-zfs-setup.md` |
| `docs/kepler-ai-serving.md` → `docs/reference/` | `CLAUDE.md` | 204, 217 | `docs/reference/kepler-ai-serving.md` |
| `docs/proposals/2026-06-20-archinaut-kernel-direct-boot.md` → `implemented/` | `CLAUDE.md` | 244 | new path |
| `docs/proposals/archinaut-migration-plan.md` (deleted) | `CLAUDE.md` | 245 | remove ref or point to archinaut-kernel-direct-boot |

The repo root `README.md` has no docs links — nothing to fix there.

## 9. Phases

Resequenced so the safety net exists **before** the file moves it protects.

1. **Index + status pass (no moves).** Fix the dead superpowers link, add the 8
   missing index rows, surface each doc's existing status, fill the two missing
   `**Status:**` lines, add the README legend. Every status is **fact-based**
   (§3) — verified against repo/deployment, not inferred. Lowest risk;
   immediately useful.
2. **Add `just docs-check` (report-only), wire into `just check`.** Flags
   broken in-repo markdown links and index rows with no file. This is the cure
   for the drift that caused this proposal, and it must land **before** any
   moves so Phases 3–5 run with a net, not without one.
3. **Relocate + refresh INSTALL.** `git mv INSTALL.md docs/guides/install.md`,
   apply §4 edits, fix the `docs/README.md` link, fix INSTALL's own
   `kepler-zfs-setup` links. `docs-check` confirms zero broken links after.
4. **Create `implemented/`, move shipped designs, delete done docs.** Move the
   fact-verified implemented docs (§6) as-is — no renumbering, no ADR rewrite.
   **Delete** finished execution checklists / superseded plans (e.g.
   `archinaut-migration-plan.md`) rather than archive them. Restore or rewrite
   the dendritic design. Carry supersession/variant notes into the index.
   Update `CLAUDE.md` references.
5. **Create `guides/` + `reference/`, move the rest.** Update `CLAUDE.md` and
   `modules/hosts/kepler/hardware.nix` doc paths.

Each phase is one commit/PR. Use `git mv` so history follows the file;
`docs-check` gates every phase from 2 onward.

## 10. Verification

- `just docs-check` (once it exists) passes — no broken in-repo markdown links.
- Manual grep confirms zero remaining references to old doc paths
  (`grep -rn "INSTALL.md\|superpowers\|docs/kepler" --include=*.md --include=*.nix --include=justfile .`).
- `just lint && just fmt-check` still pass (docs-only).
- **No dry-build needed.** The only `modules/` touch is a doc-path string inside
  a comment in `hardware.nix`; comment edits change no evaluated value, so the
  `toplevel` derivation is identical. (v1 wrongly called for a kepler
  dry-build here.)

## 11. Open questions (human judgment)

1. **Dendritic design doc** — you deleted it. Restore from git into
   `implemented/` (historical record), or write a fresh short "dendritic
   contract" note instead (which the repo-structure proposal Phase 0 also
   wants)? Recommendation: do the short contract, link the old one from git
   history if needed.
2. **Repo-hygiene in INSTALL** — link to `CLAUDE.md` (recommended) or duplicate?
3. **Status accuracy** — confirm the §6 "(verify)" rows before moving anything
   into `implemented/` (or deleting them).
4. **Folder names** — `architecture/` vs `adr/`, `reference/` vs `operational/`.
   Bikeshed now, not after the moves.
