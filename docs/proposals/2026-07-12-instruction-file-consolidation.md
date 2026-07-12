# Instruction File Consolidation Proposal

**Status:** Draft — awaiting maintainer review. No code changes proposed
beyond this document.
**Audience:** Maintainer of `desktop-nixos` and the sibling repo fleet.
**Post-read action:** Pick which phases to implement. Each phase is
independent; phases 1 and 2 are the high-value ones.

## 1. Executive summary

The repository root carries **three** overlapping instruction surfaces for
AI coding agents, layered implicitly across two tools (opencode + Codex)
and one dormant framework (BMAD). The layering works today only because
opencode's Claude Code compat fallback silently reads `CLAUDE.md` when no
`AGENTS.md` exists at repo root. This is fragile and undocumented.

This proposal:

1. Renames `CLAUDE.md` → `AGENTS.md` at repo root so opencode's canonical
   convention is explicit, not fallback-relied-upon.
2. Relocates the dormant BMAD install (`_bmad/` + 52 `.claude/commands/bmad-*`
   stubs) out of the repo root's visual path, into a clearly-dormant
   subtree.
3. Adds codex project-level instructions (currently absent — codex runs in
   this repo with only global `~/.codex/AGENTS.md`, no project orientation).
4. Documents the layering explicitly so the next agent (or future-you)
   knows which file wins for which tool.

`opencode.json` at repo root is **not** out of place — see §3.1. Every
sibling repo that uses opencode has it at root; that's the standard
convention.

## 2. Current state (evidence)

Surveyed `desktop-nixos` + 10 sibling repos on 2026-07-12.

### 2.1 Repo root files (desktop-nixos)

| File | Size | Role | Tracked |
|---|---|---|---|
| `CLAUDE.md` | 27.0K | Claude Code project rules; opencode falls back to this (no `AGENTS.md` at root) | yes |
| `opencode.json` | 1.3K | opencode project config (permissions + MCP) | yes |
| `_bmad/` | tree | BMAD framework install (commands, agents, workflows, config.yaml `platform: claude-code`) | yes |
| `.claude/commands/` | 52 files | BMAD command stubs (Claude Code-specific; invisible to opencode) | yes |
| `.claude/settings.local.json` | 1.8K | Claude Code local settings (allow-list) | yes |
| `AGENTS.md` | — | **absent** | — |
| `CODEX.md` / `.codex` | — | **absent** | — |

### 2.2 Sibling repo `opencode.json` presence

| Repo | `opencode.json` at root | Size |
|---|---|---|
| `desktop-nixos` | yes | 1.3K |
| `servarr` | yes | 993B |
| `hermes-flake` | yes | 638B |
| `homelab-iac` | yes | 945B |
| `home-assistant-config` | yes | 944B |
| `klipper-biqu` | yes | 748B |
| `homelab-gitops` | no | — |
| `kindle-dash` | no | — |
| `hermes-skills` | no | — |
| `opencode-flake` | no | — |
| `codex-flake` | no | — |
| `ha-agent` | no | — |

**Conclusion:** `opencode.json` at repo root is the established convention
across this fleet for any repo that uses opencode. Six repos do it. It is
not out of place.

### 2.3 Global instruction state (HM-managed)

| Path | HM module | Source-of-truth |
|---|---|---|
| `~/.config/opencode/AGENTS.md` | `opencode-flake` → `modules/dev/opencode.nix` `agents.extraText` | `modules/dev/opencode-agents.md` |
| `~/.config/opencode/opencode.json` | `opencode-flake` → `programs.opencode.settings` | `modules/dev/opencode.nix` |
| `~/.codex/AGENTS.md` | `codex-flake` → `programs.codex-profile.agents.{preamble,extraText}` | generated (preamble + RTK + style + extraText) |
| `~/.codex/RTK.md` | `codex-flake` → `programs.codex-profile.rtkFile` | generated |
| `~/.claude/CLAUDE.md` | (hand-managed, not HM) | hand-edited — defensive commit rules |

`OPENCODE_DISABLE_CLAUDE_CODE=1` is set via `opencode-flake`
(`disableClaudeFallback` option, default true), so opencode does NOT fall
back to `~/.claude/CLAUDE.md`. The repo-level `CLAUDE.md` is the only
Claude Code compat path still active, via opencode's local-file traversal.

### 2.4 opencode precedence (per docs, 2026-07-12)

> When opencode starts, it looks for rule files in this order:
> 1. Local files by traversing up from the current directory (`AGENTS.md`, `CLAUDE.md`)
> 2. Global file at `~/.config/opencode/AGENTS.md`
> 3. Claude Code file at `~/.claude/CLAUDE.md` (unless disabled)
>
> The first matching file wins in each category.

Today: no local `AGENTS.md` → opencode reads local `CLAUDE.md` (item 1
fallback). Global `~/.config/opencode/AGENTS.md` is ALSO loaded (item 2,
separate category). `~/.claude/CLAUDE.md` is skipped (env var disabled).

So the live layering for opencode in this repo is:
`CLAUDE.md` (project) **AND** `~/.config/opencode/AGENTS.md` (global ethos)
combined. Neither file alone is sufficient. Both load every session.

### 2.5 Codex layering

`~/.codex/AGENTS.md` (global, HM-managed) loads every Codex session. No
project-level instructions exist for `desktop-nixos`. Running `codex` in
this repo gives the agent the global ethos + RTK rules + caveman style,
but zero project architecture orientation, no synergies map, no
module-naming convention, no `just` recipe canonicality, no defensive
commit patterns for this repo specifically.

This is a gap, not a bug today — but it bites when codex is invoked for
real work in this repo.

## 3. Proposal

### 3.1 `opencode.json` at root — no change

**Decision:** keep `opencode.json` at repo root. It follows the
fleet-wide convention (6/6 opencode-using repos do this). It carries
permissions + MCP server config that are genuinely project-specific.
Moving it gains nothing and breaks the pattern siblings follow.

### 3.2 Phase 1 — rename `CLAUDE.md` → `AGENTS.md` at repo root

**Why:** opencode's canonical convention is `AGENTS.md`; `CLAUDE.md` is
the Claude Code compat fallback. Today we rely on the fallback
silently. Renaming makes the canonical path explicit and removes the
implicit dependency on compat-shim behavior. Any future opencode
version that tightens the compat fallback (or removes it) won't break
us.

**Blast radius:**
- `git mv CLAUDE.md AGENTS.md` — no content change.
- Update the one cross-reference at L113 of the (renamed) file:
  `~/.claude/CLAUDE.md` is still the source for defensive commit rules;
  the rename is local to this repo, the global file is untouched.
- Verify no `.claude/commands/*` stub or `_bmad/config.yaml` hard-codes
  `CLAUDE.md` as the instruction source — survey says they don't (BMAD
  uses `_bmad/bmm/agents/*.agent.yaml` and `workflow.md` paths, not the
  repo root instruction file).
- `.claude/settings.local.json` — does not reference `CLAUDE.md` by name
  (it carries permission allow-lists only).

**Claude Code compat:** Claude Code reads `CLAUDE.md` at repo root. After
rename, Claude Code loses project instructions for this repo. Two
options:

- **A) Accept the loss.** Claude Code falls back to `~/.claude/CLAUDE.md`
  (defensive commit rules only). Project architecture orientation is
  gone for Claude Code sessions. If Claude Code is not used in this
  repo, this is fine.
- **B) Symlink `CLAUDE.md` → `AGENTS.md`.** Both tools read the same
  content. Claude Code reads `CLAUDE.md` (symlink), opencode reads
  `AGENTS.md` (target). One source of truth. Costs one extra repo-root
  entry (a symlink).

**Recommendation:** B (symlink). Zero maintenance cost, both tools
served, no content duplication.

### 3.3 Phase 2 — relocate dormant BMAD install

**Why:** Per the "Canonical vs dormant" declaration added to
`modules/dev/opencode-agents.md` (2026-07-12), spicyphus per-slice is
canonical; BMAD is dormant — invoke only by explicit `@`-mention. Today
the dormant framework occupies the repo root's visual path (`_bmad/` +
52 command stubs in `.claude/commands/`). That contradicts its dormant
status: root-level placement signals "active", not "dormant".

**Blast radius:**
- `git mv _bmad/ modules/dev/_dormant-bmad/` (or `.dormant/bmad/`).
- `git mv .claude/commands/bmad-*.md .claude/commands/bmalph-*.md` into
  the same dormant subdir. Keep non-BMAD `.claude/commands/` stubs (if
  any) in place.
- Update `_bmad/config.yaml` `output_folder` + `planning_artifacts` +
  `implementation_artifacts` paths if they absolutize.
- Add a one-line note in the dormant README: "Invoke only via explicit
  `@`-mention per global AGENTS.md canonical-vs-dormant declaration."
- `.claude/settings.local.json` — does not reference `_bmad/` paths; no
  change needed.

**Risk:** `bmalph` (the BMAD installer/updater) may re-create `_bmad/`
on the next `bmalph-upgrade` or `bmalph-implement` run. If so, the
dormant relocation needs to be re-applied after each BMAD operation, OR
we accept that BMAD operations recreate the root-level install and we
re-relocate after. This is a tooling quirk to confirm before committing
to Phase 2.

**Alternative — Phase 2':** delete `_bmad/` + `.claude/commands/bmad-*`
entirely. Per the dormant declaration, they're escape hatches, not the
default path. If the escape hatch is never used, deletion is cleaner
than relocation. Re-install via `npx @bmad-method/bmalph` if ever needed
again. This is the most opinionated option.

**Recommendation:** Phase 2' (delete) if BMAD has not been invoked in
the last 30 days; Phase 2 (relocate) if it has. Maintainer decides
based on usage history.

### 3.4 Phase 3 — codex project instructions

**Why:** Codex has no project-level instructions for `desktop-nixos`
today. Global `~/.codex/AGENTS.md` (HM-managed) carries ethos + RTK +
caveman style, but nothing about this repo's architecture, synergies,
module naming, `just` recipe canonicality, or defensive commit
patterns. A codex session in this repo is blind to project context.

**Convention:** Codex CLI reads `AGENTS.md` at project root (same
convention as opencode). If Phase 1 renames `CLAUDE.md` → `AGENTS.md`,
codex inherits the project instructions automatically — same file
serves opencode + codex + (via symlink) Claude Code.

**Verify before committing:** confirm with `codex doctor` or
`codex --help` that project-root `AGENTS.md` is read. The
`codex-flake` HM module manages `~/.codex/AGENTS.md` (global); it does
NOT manage a project-level file. Codex's project-level convention
should be verified empirically before assuming Phase 3 is "free" from
Phase 1.

**If codex does NOT read project `AGENTS.md`:** add a
`~/.codex/instructions.md` reference (or a `-c instructions=...` config
key) pointing to the repo's `AGENTS.md`. This is a `codex-flake` module
change, not a `desktop-nixos` change — sister-repo blast radius. Open
an RFC in `codex-flake` if this path is needed.

**Recommendation:** do Phase 1 first, then verify codex's behavior. If
codex reads project `AGENTS.md`, Phase 3 is free. If not, open a
codex-flake RFC.

### 3.5 Phase 4 — document the layering

**Why:** the layering is currently tacit. The next agent (or future-you)
has to infer which file wins for which tool from the opencode docs +
codex-flake module + evicted CLAUDE.md compat shim. That's three sources
to synthesize. Write it down once.

**Where:** append a `## Instruction file layering` section to the repo's
`AGENTS.md` (renamed from `CLAUDE.md`). Content:

```
## Instruction file layering

This repo uses three instruction surfaces for AI coding agents:

| Tool | Project instructions | Global instructions |
|---|---|---|
| opencode | `AGENTS.md` (repo root) | `~/.config/opencode/AGENTS.md` (HM-managed via `opencode-flake`, source: `modules/dev/opencode-agents.md`) |
| Codex | `AGENTS.md` (repo root, same file) | `~/.codex/AGENTS.md` (HM-managed via `codex-flake`) |
| Claude Code | `CLAUDE.md` → symlink to `AGENTS.md` | `~/.claude/CLAUDE.md` (hand-managed, defensive commit rules) |

opencode precedence: local `AGENTS.md` + global `~/.config/opencode/AGENTS.md`
both load. `~/.claude/CLAUDE.md` is skipped (`OPENCODE_DISABLE_CLAUDE_CODE=1`).

Canonical workflow: spicyphus per-slice loop (see global AGENTS.md
"Per-slice TDD mechanics"). BMAD (`_bmad/` or `modules/dev/_dormant-bmad/`)
is dormant — invoke only by explicit `@`-mention.
```

**Blast radius:** one new section in the renamed `AGENTS.md`. No code
change.

## 4. Decisions required

| Phase | Decision | Blast radius |
|---|---|---|
| 1 | Rename `CLAUDE.md` → `AGENTS.md`, add `CLAUDE.md` symlink | repo only |
| 2 | Relocate BMAD to dormant subdir, OR delete entirely | repo only (verify bmalph re-install behavior) |
| 3 | Verify codex reads project `AGENTS.md`; if not, open codex-flake RFC | repo + possibly sister |
| 4 | Document the layering in renamed `AGENTS.md` | repo only |

## 5. What this proposal does NOT do

- Does not move `opencode.json` out of repo root. It's the fleet
  convention; keep it.
- Does not consolidate global ethos files. `~/.config/opencode/AGENTS.md`
  (spicyphus doctrine) and `~/.claude/CLAUDE.md` (defensive commit rules)
  stay separate. They serve different purposes and are managed by
  different mechanisms (HM vs hand). Folding them risks drift and mixes
  the two registers (why vs what/how) the global AGENTS.md explicitly
  separates.
- Does not add codex project instructions as a separate file. If codex
  reads project `AGENTS.md` (Phase 3 verification), one file serves
  both tools. If not, the codex side is a codex-flake change, not a
  desktop-nixos change.
- Does not touch sibling repos. Their `opencode.json` at root is their
  convention; their lack of `CLAUDE.md` is their call. This proposal is
  `desktop-nixos`-scoped.

## 6. Verification

Per-phase verify commands:

- **Phase 1:** `git diff --stat` shows rename only. `just dry laptop`
  passes (sanity — no Nix change). Start an opencode session in the
  repo; confirm `AGENTS.md` is loaded (check via `/context` or the
  first response carrying the canary token).
- **Phase 2:** `just dry laptop` passes. Start an opencode session;
  confirm `@bm-architect` (or any BMAD `@`-mention) still resolves if
  Phase 2 (relocate) was chosen. If Phase 2' (delete), confirm BMAD
  `@`-mentions no longer resolve (expected).
- **Phase 3:** `codex doctor` in the repo; inspect which instruction
  files it reports loading. If `AGENTS.md` is listed, Phase 3 is done.
  If not, document the gap and open a codex-flake issue.
- **Phase 4:** new `AGENTS.md` section renders cleanly; no broken
  markdown.

## 7. Open questions

1. Has BMAD been invoked in the last 30 days? (Determines Phase 2 vs
   Phase 2'.) Check `.claude/commands/bmad-*` git log or `_bmad-output/`
   presence.
2. Does codex CLI read project-root `AGENTS.md`? (Determines if Phase 3
   is free.) Verify with `codex doctor` before assuming.
3. Is `~/.claude/CLAUDE.md` (hand-managed) worth folding into
   `~/.config/opencode/AGENTS.md` (HM-managed)? This proposal says no
   (see §5), but the maintainer may want to revisit separately.