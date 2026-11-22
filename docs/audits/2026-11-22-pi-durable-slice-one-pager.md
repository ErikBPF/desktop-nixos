# Pi durable harness MVP — one-pager

**Date:** 2026-11-22
**Stage:** Implementation verified in a worktree. No deploy, no push, no new repo.
**Worktree:** `desktop-nixos/worktrees/pi-durable-20261122`, branch
`feat/pi-durable-harness`.
**Audit:** [`2026-11-22-pi-durable-slice.md`](2026-11-22-pi-durable-slice.md)

## Outcome and why

The harness is a Pi-native coding agent, not an OpenCode clone. Pi durable owns
conversations, tasks, gates, storage, and restart recovery. The package wires
the two home gateways, coding tools, code mode, MCP tools, and background
subagents into one registry and exposes four CLI commands.

The slice delivers a working local MVP: it builds under npm and Nix, passes
offline tests, and answered one live LiteLLM request. It is not deployed and is
not wired into `modules/dev/pi.nix`.

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
- `default.nix`: `buildNpmPackage`, hash obtained from the build.
- `test/`: faux-provider conversation, subagent ownership and reuse, code-mode
  output filtering, in-memory MCP bridge.
- `README.md`: run instructions, storage, credentials, and limits.

## Evidence and limits

- `npm install --ignore-scripts`: 153 packages.
- `npm run build`: TypeScript emits `dist/` with no errors.
- `npm test`: 5 files, 9 tests passed.
- `nix build --file ./default.nix`: `/nix/store/0cs48aphxmhr2qlna573ahpr0jy17xbq-pi-harness-0.1.0`.
- Live `ask` through LiteLLM printed `ok`; usage was input 11,432, output 3,
  total 11,435, cost `$0.003433`. The task was under 200 tokens; the project
  `AGENTS.md` instructions dominate the request.
- First live attempt failed with `400` because LiteLLM requires
  `x-opencode-session`. The provider now sends a stable per-process value.
- No key was printed. No OpenCode file changed. `modules/dev/pi.nix` was not
  edited; that file lives in another worktree.

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

## Continuing work

- Add a crash-replay test for code mode that reopens mid-script.
- Exercise `work/deepseek-v4.1-flash` and `work/glm-5.3-flash` live.
- Decide whether `status` should avoid a read-only commit when scanning
  conversations.
- Wire into a home profile only after a separate permission/sandbox decision.

## Risks and recovery

The largest risk is assuming durable's restart path is exercised because the
package builds. Only unit-level guards were observed. Recovery is local: delete
the test state directory or the target `.db`; source changes stay in this
worktree. Do not run two writers on one database.
