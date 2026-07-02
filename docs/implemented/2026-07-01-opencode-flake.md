# opencode-flake

**Status:** ✅ Implemented (2026-07-02) — all four slices live.
`github.com/ErikBPF/opencode-flake` (FlakeHub-published, daily auto-merge
updater, `opencode-v*` tags); laptop adopted `withPackage` and migrated per
§5. Deviations from this RFC: **no Cachix** — the fleet substitutes from
orion's nix-serve (warmed nightly by `nix-cache-builder`), so a third-party
cache would serve nobody; CI `package-build` is a required verification
gate instead. And the profile installs `pkgs.opencode` by default (upstream
`programs.opencode` crashes on `package = null`, so files-only was
impossible).
**Date:** 2026-07-01.
**Audience:** Maintainer of `codex-flake`, `hermes-flake`, and `desktop-nixos`.

## 1. Context

opencode is already in daily use with a hand-managed global config
(`~/.config/opencode/opencode.json` + `tui.json`), tuned in
[`implemented/2026-06-29-opencode-improvements.md`](../implemented/2026-06-29-opencode-improvements.md).
A project-level `opencode.json` also exists in `hermes-flake` (permission
guardrails + mcp-nixos). None of this is declarative today.

Two sibling flakes set the precedent:

- `codex-flake` — profile-first Home Manager module (AGENTS.md, inline RTK,
  caveman style) plus an opt-in fast package lane
  ([`implemented/2026-06-30-codex-flake-update-strategy.md`](../implemented/2026-06-30-codex-flake-update-strategy.md)).
- `hermes-flake` — package-owning flake with hardened auto-update
  ([`implemented/2026-06-30-hermes-flake-update-hardening.md`](../implemented/2026-06-30-hermes-flake-update-hardening.md)).

The reference model both borrow from is `sadjow/claude-code-nix`: hourly
version check → script-verified bump → auto-merged PR → Cachix push →
immutable `vX.Y.Z` tag + moving `vX`/`latest` channel tags.

## 2. Why opencode needs *less* flake than codex did

Research findings (2026-07-01) that shape the design:

- **nixpkgs already packages opencode well** (`pkgs.opencode`, v1.17.9,
  `pkgs/by-name/op/opencode/package.nix`): Bun single-binary build, FOD
  `node_modules` sub-derivation (`nix-update-script --subpackage
  node_modules`), vendored models.dev catalog
  (`OPENCODE_DISABLE_MODELS_FETCH`), wrapper sets
  `OPENCODE_DISABLE_AUTOUPDATE=true` + ripgrep on PATH, and ships the
  generated JSON schemas as `passthru.jsonschema`.
- **home-manager master already has a mature `programs.opencode`**:
  `settings` → `opencode.json` (DAG-ordered rendering because permission
  rules are last-match-wins), separate `tui.json` handling,
  agents/commands/tools/skills/themes directories, `programs.mcp` bridge,
  `web.enable` for `opencode serve` with `environmentFile`.
- **Declarative config is safe here, unlike Codex.** opencode does not write
  back into `opencode.json`; mutable state (auth.json, sessions, logs) lives
  in `~/.local/share/opencode/`. Config supports `{env:VAR}` / `{file:path}`
  substitution — sops secrets without plaintext in the store.
- **Instruction-file trap:** with no global `AGENTS.md`, opencode falls back
  to reading `~/.claude/CLAUDE.md` (disable via
  `OPENCODE_DISABLE_CLAUDE_CODE`).

## 3. Resolved decisions

2026-07-01:

- **D1 — instructions:** dedicated global `AGENTS.md` managed by the flake,
  with RTK guidance inlined (codex-flake pattern), and
  `OPENCODE_DISABLE_CLAUDE_CODE` set. Rationale: `~/.claude/CLAUDE.md`
  contains Claude-harness-specific prose; instruction files should be
  tool-shaped.
- **D2 — module strategy:** **wrap** upstream `programs.opencode`, do not
  reimplement file plumbing. The flake layers opinionated profile content on
  top; upstream owns rendering, DAG ordering, and directory handling.

2026-07-02:

- **D3 — profile scope:** **G1 permissions + G3 theme/tui** migrate into the
  flake (each behind its own enable flag). **G2 provider policy stays
  host-local** in `desktop-nixos` — it couples to the LiteLLM endpoints and
  keys of this fleet, not to a reusable profile.
- **D4 — cadence:** daily updater + auto-merge behind required checks
  (including schema validation). Same posture as codex-flake; revisit hourly
  only after Cachix hit rate is proven.
- **D5 — consumption:** FlakeHub rolling wildcard, publish gated on required
  checks — same flow as codex-flake.
- **D6 — migration:** adopt-port-delete. Port current `opencode.json` /
  `tui.json` values into flake/module settings, back up then remove the
  hand-managed files, HM owns from the first switch. No seed-if-missing on
  the laptop.

## 4. Proposed shape

| Layer | Content |
|-------|---------|
| Profile module (default) | Sets `programs.opencode.*`: permission guardrails (`flake.lock: ask`, `*.sops`/`*.env*`/`*.age`: deny — pattern from `hermes-flake/opencode.json`), theme/tui (tokyonight, enable-flagged), mcp-nixos entry, global `AGENTS.md` with inline RTK + caveman style, `OPENCODE_DISABLE_CLAUDE_CODE` session var. Provider policy (G2) is **not** in the flake — host-local (D3). Package = consumer's `pkgs.opencode`. |
| `homeManagerModules.withPackage` | Opt-in fast lane: flake-owned `packages.opencode` (nixpkgs-derived expression, `nix-update --subpackage node_modules`), daily updater CI, auto-merge behind required checks, `opencode-v*` tags. Reuse codex-flake workflow files. |
| Checks | Validate the generated `opencode.json` / `tui.json` against `passthru.jsonschema.config` / `.tui` in `nix flake check` — schema-verified config, which neither codex-flake nor hermes-flake can do. Plus lint + module-render + package-default-off checks (codex-flake suite). |
| Distribution | **Cachix from day one** (gap identified in codex-flake: auto-bumps without a warm cache force consumers to rebuild). Moving channel tags alongside immutable ones, per claude-code-nix. |

## 5. Migration plan (D6)

1. Snapshot `~/.config/opencode/` to `~/backups/opencode-preflake-<date>/`.
2. Port `opencode.json` values: G1 permissions + mcp entries → flake profile
   defaults; G2 provider block → `desktop-nixos` host-local
   `programs.opencode.settings`.
3. Port `tui.json` (tokyonight + attention) → flake G3 section.
4. Remove the hand-managed files; `home-manager switch`; diff rendered files
   against the snapshot — only expected deltas (`$schema` line, key order).
5. Smoke: launch opencode, confirm permissions/theme/mcp behave; confirm
   `~/.claude/CLAUDE.md` is not ingested.

## 6. Non-goals

- Do not manage auth or session state (`~/.local/share/opencode/`).
- Do not fork or replace upstream `programs.opencode` (D2).
- No NixOS system module; opencode is a per-user tool.

## 7. Verification (when implemented)

- `nix flake check`: schema validation of rendered configs, lint, module
  render, package off by default.
- Consumer smoke: `opencode --version` matches the packaged version;
  `AGENTS.md` present; `opencode` does not read `~/.claude/CLAUDE.md`.
- Update script `--check` has deterministic exit codes (contract shared with
  codex/hermes updaters).

## 8. Implementation slices

1. **Repo + profile module:** flake scaffold (codex-flake layout), profile
   module wrapping `programs.opencode` (G1 + AGENTS.md + mcp-nixos +
   `OPENCODE_DISABLE_CLAUDE_CODE`), G3 theme section, checks incl. schema
   validation via `passthru.jsonschema`.
2. **Package lane:** `packages.opencode` from the nixpkgs expression,
   `scripts/update-opencode.sh` (`--check`/`--version` contract), Cachix
   push wired before any auto-merge is enabled.
3. **CI:** daily updater PR flow + auto-merge behind required checks,
   `opencode-v*` tags, FlakeHub publish + verify (copy codex-flake
   workflows; pin actions by SHA from the start).
4. **Consumer adoption:** desktop-nixos imports `withPackage` from the first
   verified FlakeHub release; run the §5 migration on the laptop.
