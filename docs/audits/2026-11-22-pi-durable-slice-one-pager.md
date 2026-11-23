# Pi durable harness MVP — one-pager

**Date:** 2026-11-22
**Status:** Implemented, wired into `m.home.pi`, not switched on a host.
**Worktree:** developed in `desktop-nixos/worktrees/pi-durable-20261122` on
branch `feat/pi-durable-harness`; landed with the shadow slice
(`feat/pi-shadow-20261122`, PR #525).
**Audit:** [`2026-11-22-pi-durable-slice.md`](2026-11-22-pi-durable-slice.md)

## Outcome and why

The harness is a Pi-native coding agent, not an OpenCode clone. Pi durable owns
conversations, tasks, gates, storage, and restart recovery. The package wires
the two home gateways, coding tools, code mode, MCP tools, and background
subagents into one registry and exposes four CLI commands.

The slice delivers a working local MVP: it builds under npm and Nix, passes
offline tests, and answered one live LiteLLM request. `modules/dev/pi.nix`
installs it as `pi-harness`, and `profile-desktop` imports `m.home.pi`. No host
was switched, so the command is not active on a machine yet. The upstream `pi`
agent is unchanged and keeps the interactive command.

## Changes

- `modules/dev/pi-harness/src/providers.ts`: `litellm` and `work` providers with
  request-time key resolution, costs and limits from `modules/dev/opencode.nix`,
  and the LiteLLM routing header.
- `src/harness.ts`: SQLite storage, coding tools with Node Photon images, image
  fitting, 256 MiB QuickJS code mode, tool search, MCP bridges with deferred
  tools, and the default agent using the project `AGENTS.md`.
- `src/subagent.ts`: one `subagent` tool (`spawn`, `send`, `wait`, `stop`,
  `list`). Children are owned background conversations, use a cheaper model, and
  cannot recurse. Reporter tasks use request IDs for delivery and reporting.
- `src/cli.ts`: `ask`, `resume`, `status`, `watch`, plus `--project`,
  `--model`, `--thinking`, `--state-dir`, `--no-mcp`.
- `default.nix`: flake-parts module exposing `packages.pi-harness`.
- `modules/dev/pi.nix`: installs the harness as `pi-harness` beside the
  upstream `pi` agent.
- `_package.nix`: `buildNpmPackage`, with a hash obtained from the build.
- `test/`: faux-provider conversation, subagent ownership and reuse, code-mode
  output filtering, in-memory MCP bridge.
- `README.md`: run instructions, storage, credentials, and limits.

## Evidence and limits

- `npm install --ignore-scripts`: 153 packages.
- `npm run build`: TypeScript emits `dist/` with no errors.
- `npm test`: 7 files, 20 tests passed (after the review fixes).
- `nix build .#pi-harness`:
  `/nix/store/m2zqglcfksvs93d80wdw5g601kjngb1d-pi-harness-0.1.0`.
- `nix flake show` and `just lint`, `just fmt-check`, `just docs-check` pass.
- Home Manager path for `endeavour`: `bin/pi-harness` prints the harness USAGE
  and `bin/pi` is the upstream agent.
- Live `ask` through LiteLLM printed `ok`; usage was input 10,940, output 3,
  cost `$0.000821`. A plain `resume` kept `litellm/glm-5.3-flash`.
- First live attempt failed with `400` because LiteLLM requires
  `x-opencode-session`. The provider now sends a stable per-process value.
- No key was printed. No OpenCode file changed.

Limits: coding tools are unsandboxed and ungated; code mode limits memory, not
authority. MCP startup is best effort. The `work` provider was not exercised
live. Code-mode journal replay and a process restart during a subagent report
were not simulated; the tests prove the idempotency guards, not the crash path.

## Decisions

1. Pin `@earendil-works/*` at 1.6.0 and read examples from that tag.
2. Use durable's code-mode extension and sandbox; do not reimplement the journal.
3. Build the MCP durable bridge in `harness.ts`; `pi-mcp` ships only a client.
4. Keep MCP failures non-fatal so `ask` still works without the local servers.
5. Child model defaults to `litellm/glm-5.3-flash`.
6. `pi-env` is declared per the slice contract but not imported directly; MCP
   stdio is spawned by `pi-mcp`.
7. `default.nix` is a flake-parts module; `_package.nix` holds the derivation
   because import-tree skips `_`-prefixed files.
8. `root.configure()` changes `--model`, `--thinking`, `cwd`, or instructions
   only when the flag is passed or the on-disk value differs; a plain `resume`
   leaves the stored agent alone.
9. The database name includes a hash of the absolute project path.

## Continuing work

- Add a crash-replay test for code mode that reopens mid-script.
- Exercise `work/deepseek-v4.1-flash` and `work/glm-5.3-flash` live.
- Decide whether `status` should avoid a read-only commit when scanning
  conversations.
- Decide the permission/sandbox posture before switching a host. The profile
  wiring itself is done.

## Review fixes (2026-11-22)

The first real read-only run reviewed the harness and found five defects. All
five were confirmed against the pinned type declarations and fixed on
`feat/pi-shadow-20261122`: exact-id entry lookup (with a RED test that puts the
answer outside the 200-entry window), settled-reason failure reporting with a
`turn_limit` faux run, bounded `status` paging whose count matches its rows,
sandbox ownership on `close()`, and corrected USAGE default text. A fresh
whole-slice review then found a symlinked-entrypoint regression, a vacuous
stale-failure assertion, and an unproven exact-query test; all were fixed with
tests. Evidence: 13 → 20 tests, `tsc --noEmit`, `nix build .#pi-harness`,
`just lint`, `just fmt-check` all pass. Details and rejected alternatives:
[`2026-11-22-pi-harness-review-fixes.md`](2026-11-22-pi-harness-review-fixes.md).

## Risks and recovery

The largest risk is assuming durable's restart path is exercised because the
package builds. Only unit-level guards were observed. Recovery is local: delete
the test state directory or the target `.db`; source changes stay in this
worktree. Do not run two writers on one database.
