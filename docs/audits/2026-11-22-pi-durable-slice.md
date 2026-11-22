# Pi durable harness MVP — slice audit

**Date:** 2026-11-22
**Status:** Implemented in a worktree; no deploy, no repository creation, no push.
**Owner repo:** `desktop-nixos`, worktree `pi-durable-20261122`, branch
`feat/pi-durable-harness`.

## Outcome

The `modules/dev/pi-harness/` TypeScript package builds, tests offline, packages
with Nix, and answered one live request through LiteLLM.

The harness is Pi-native. Pi durable owns conversations, tasks, gates, storage,
and restart recovery. There is no OpenCode permission engine, role server, port
allocation, or backend wrapper.

## What was added

- `package.json`, `package-lock.json` — exact `@earendil-works/*` 1.6.0,
  TypeScript 5.9.3, tsx 4.23.15, vitest 3.2.4, `@types/node` 24.19.2.
- `tsconfig.json` — NodeNext ESM build to `dist/`.
- `src/providers.ts` — `litellm` and `work` providers, request-time key
  resolution from the sops files with the documented environment fallback,
  costs and limits from `modules/dev/opencode.nix`.
- `src/harness.ts` — SQLite storage under
  `${XDG_STATE_HOME:-~/.local/state}/pi-harness/<project>-<hash>.db`, coding tools with
  Node Photon images, image fitting, code mode with a 256 MiB QuickJS sandbox,
  tool search, MCP bridges, and the default agent (`AGENTS.md` instructions,
  project `cwd`).
- `src/subagent.ts` — one `subagent` tool with `spawn`, `send`, `wait`, `stop`,
  `list`; children are separate conversations owned by a background anchor,
  start from the parent's agent, use a cheaper model, and have no subagent tool.
  Reporter tasks use request IDs for the message and the report.
- `src/cli.ts` — `ask`, `resume`, `status`, `watch` with `--project`,
  `--model`, `--thinking`, `--state-dir`, `--no-mcp`.
- `default.nix` — flake-parts module that exposes `packages.pi-harness`.
- `_package.nix` — `buildNpmPackage` with a hash obtained from the build;
  import-tree skips the file because its name starts with `_`.
- `README.md` — usage, storage, credentials, and explicit limits.
- `test/` — faux-provider conversation, subagent, code mode, and in-memory MCP
  tests.

No OpenCode file changed. `modules/dev/pi.nix` does not exist in this worktree
and was not edited; worktree `pi-shadow-20261122` was not touched.

## Verification (run in this worktree)

```text
$ npm install --ignore-scripts
added 153 packages in 16s

$ npm run build
> tsc -p tsconfig.json
(no output)

$ npm test
Test Files  5 passed (5)
Tests       11 passed (11)

$ nix build .#pi-harness --no-link --print-out-paths
/nix/store/lm5rp38hdrrf2q7khqrfi8kqzsskvr5p-pi-harness-0.1.0

$ nix flake show --no-write-lock-file --json
packages.x86_64-linux.pi-harness present

$ nix eval --raw .#nixosConfigurations.endeavour.config.system.build.toplevel.drvPath
(a store path; it changes with the staged tree)

$ just lint
$ just fmt-check
$ just docs-check
all pass

$ /nix/store/lm5rp38hdrrf2q7khqrfi8kqzsskvr5p-pi-harness-0.1.0/bin/pi-harness
usage: pi-harness <command> [options] ...

$ XDG_STATE_HOME=/tmp/opencode/pi-harness-final3 pi-harness status \
    --project <worktree> --no-mcp
conversations: 1
  1
live tasks: 0
usage litellm/glm-5.3-flash: input=10940 output=3 cache_read=0 total=10943 cost=$0.000821
```

### Live smoke (ran)

```text
$ XDG_STATE_HOME=/tmp/opencode/pi-harness-final3 pi-harness ask \
    "Reply with exactly: ok" --project <worktree> --no-mcp \
    --model litellm/glm-5.3-flash --thinking low
model: litellm/glm-5.3-flash
ok
usage litellm/glm-5.3-flash: input=10940 output=3 cache_read=0 total=10943 cost=$0.000821

$ XDG_STATE_HOME=/tmp/opencode/pi-harness-final3 pi-harness resume \
    --project <worktree> --no-mcp
model: litellm/glm-5.3-flash
ok
usage litellm/glm-5.3-flash: input=10940 output=3 cache_read=0 total=10943 cost=$0.000821
```

The task text is under 200 tokens. The request was not: the default agent sends
the project `AGENTS.md` (30.7 KB) as instructions. The first attempt failed with
`400 ... missing x-opencode-session`; the fix is a stable per-process routing
header on the LiteLLM models. No key was printed.

## Decisions

1. **Pin all Pi packages at 1.6.0.** The examples were read from tag `v1.6.0`.
2. **Use `createCodemodeExtension` and `CodemodeSandbox` from pi-durable and
   pi-codemode.** No custom sandbox or journal.
3. **Wrap MCP manually.** `pi-mcp` ships a client, not a durable extension. The
   bridge names tools with `createMcpToolName`, normalizes schemas with
   `normalizeMcpInputSchema`, and marks every tool `deferred`.
4. **Best-effort MCP startup.** A missing local server must not block `ask`.
   Failures print the server name and reason to stderr.
5. **Children use `litellm/glm-5.3-flash`.** It is the cheaper configured model.
6. **Add the LiteLLM session header on the model.** Work does not need it, so it
   stays off the Work models.
7. **Split the Nix files.** `modules/dev/pi-harness/default.nix` is a
   flake-parts module because import-tree evaluates every `.nix` file under
   `modules/`. The derivation lives in `_package.nix`, which import-tree skips.
8. **Apply the agent only when asked.** `root()` applies its agent argument
   when it creates the conversation. On reopen, `openHarness` changes the model
   or thinking level only when the caller passed that flag, and refreshes
   `instructions` or `cwd` only when they differ. Plain `resume`, `status`, and
   `watch` leave the stored agent alone.
9. **Hash the absolute project path into the database name.** Two projects with
   the same basename must not share a transcript or the first project's `cwd`.
10. **Run MCP servers in the project directory**, give tool calls 300 seconds,
    forward the abort signal, and close a client when connect or `tools/list`
    fails.
11. **`pi-env` is declared because the slice contract lists it.** No source file
    imports it directly; MCP stdio is spawned by `pi-mcp`'s transport.

## Gaps and untested claims

- No crash-replay test for a code-mode script that is interrupted mid-call. The
  test proves nested-tool output filtering, not journal replay after reopen.
  Pi durable's own replay path is used, not reimplemented.
- The subagent test proves separate ownership, a background anchor, and
  idempotent spawn by name. It does not kill and reopen the process during a
  report; reporter request IDs are the restart guard.
- The MCP client is closed when connect or `tools/list` fails, but the test suite
  does not spawn a failing stdio server to assert the process exits.
- The `work` provider was not exercised live.
- `status` scans conversations through a read-only commit on the harness line.
  It observed the expected root conversation; whether an empty commit is stored
  was not inspected.
- Coding tools are unsandboxed and ungated. Code mode limits memory, not
  authority.
- The live request cost $0.000821 because instructions dominate the prompt; a
  smaller project directory would reduce it.
- Child agents inherit the parent's instructions and append the subagent role
  line; they are not byte-for-byte copies.

## Review reconciliation

A fresh whole-slice review found one blocker and several defects. All were
addressed:

- **Blocker:** `default.nix` broke flake evaluation because import-tree treats
  every `.nix` file under `modules/` as a module. It is now a flake-parts module
  and the derivation moved to `_package.nix`. `nix flake show` and
  `nix eval .#nixosConfigurations.endeavour...` pass.
- `--model`/`--thinking` were ignored on reopen; `openHarness` now calls
  `root.configure()`.
- Two projects with the same basename shared a database; the name now includes a
  hash of the absolute path.
- A failed `tools/list` leaked the MCP child; connect now closes the client on
  failure, and `openHarness` closes clients if later setup throws.
- MCP servers now start in the project directory.
- MCP tool calls now use a 300-second timeout and the call's abort signal.
- Subagent tests now assert the owner task is the background anchor. The
  duplicate-spawn test was renamed to what it checks.
- A second review found that unconditional `root.configure()` rewrote a stored
  model and thinking level on every CLI call. `openHarness` now changes them
  only when the flag is passed, and a reopen test covers work/low → no flags →
  work/low → explicit litellm/high.
- Code-mode output is compared by its exact last line, not a loose `"2"`.
- CLI validates `--thinking`, swallows a stop rejection in `watch`, and the Nix
  source is filtered to package files.

## Paths touched

```text
modules/dev/pi-harness/README.md
modules/dev/pi-harness/_package.nix
modules/dev/pi-harness/default.nix
modules/dev/pi-harness/package-lock.json
modules/dev/pi-harness/package.json
modules/dev/pi-harness/src/cli.ts
modules/dev/pi-harness/src/harness.ts
modules/dev/pi-harness/src/providers.ts
modules/dev/pi-harness/src/subagent.ts
modules/dev/pi-harness/test/codemode.test.ts
modules/dev/pi-harness/test/conversation.test.ts
modules/dev/pi-harness/test/mcp.test.ts
modules/dev/pi-harness/test/providers.test.ts
modules/dev/pi-harness/test/subagent.test.ts
modules/dev/pi-harness/tsconfig.json
docs/audits/2026-11-22-pi-durable-slice.md
docs/audits/2026-11-22-pi-durable-slice-one-pager.md
```
