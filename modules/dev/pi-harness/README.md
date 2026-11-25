# pi-harness

A Pi-native, durable coding harness for the home model gateways and subscription accounts. It uses
`@earendil-works/pi-durable` for conversations, tasks, gates, restart recovery,
and code mode. It does not recreate OpenCode's permission engine, role servers,
ports, or backend wrapper.

## What it provides

- Gateway providers `litellm` (Orion) and `work`, direct `opencode-go`, plus native `openai-codex`
  and `anthropic` subscription providers. The approved model IDs live in
  `src/approved-models.json`. Orion includes DeepSeek V4.1 Flash, full GLM-5.3,
  and the Codex subscription aliases. Work keeps GLM-5.3 Flash.
- Coding tools (`read`, `write`, `edit`, `bash`), image fitting, code mode
  (`createCodemodeExtension` with a 256 MiB QuickJS sandbox), tool search, one
  MCP extension per configured server with deferred tools, and background
  subagents.
- SQLite storage. Conversations survive restarts. `resume` continues pending
  tasks.
- The default agent runs in the project directory and uses that project's
  `AGENTS.md` as instructions.

## Run

The Home Manager module installs the harness as `pi-harness`, beside the
upstream `pi` agent. From a checkout:

```bash
npm install --ignore-scripts
npm run build
npm test

# from source
npx tsx src/cli.ts ask "List the top-level directories." --project /path/to/repo

# built CLI
nix build .#pi-harness
./result/bin/pi-harness ask "Explain the build." --project /path/to/repo
```

Commands:

- `ask "<task>"` — submit one input, wait, print the final answer and usage.
- `resume` — reopen storage, run pending tasks, print the latest answer or the
  unsettled run failure.
- `status` — conversations, live tasks from `watchTaskGraph`, and spend.
- `watch [id]` — stream a conversation's committed entries; root by default.

Options:

- `--project <dir>` (default: current directory)
- `--model <provider/id>` (`litellm`, `work`, `openai-codex`, `anthropic`, or `opencode-go`; first creation defaults to
  `litellm/deepseek-v4.1-flash`)
- `--thinking <level>` (`off`, `minimal`, `low`, `medium`, `high`, `xhigh`,
  `max`; first creation defaults to `high`)
- `--state-dir <dir>` — override the storage root
- `--no-mcp` — do not start the donsetch and graphify MCP servers

`--model` and `--thinking` change a stored conversation only when passed. A
plain `resume`, `status`, or `watch` leaves the stored agent alone.

## Storage

`${XDG_STATE_HOME:-~/.local/state}/pi-harness/<project>-<hash>.db`, where
`<project>` is the sanitized base name of the project directory and `<hash>` is
the first eight hex characters of the absolute path. SQLite runs in WAL mode.
One process must write a database at a time; there is no cross-process locking.

## Credentials

Keys are resolved when a request is made, never at module load and never
printed:

1. `/run/secrets/opencode/litellm_key` and `/run/secrets/opencode/work_key`
2. `OPENCODE_LITELLM_KEY` and `OPENCODE_WORK_KEY`

Direct Go reads `/run/secrets/opencode/zen_key`, then `OPENCODE_API_KEY`.

LiteLLM also requires an `x-opencode-session` header. The harness sends a stable
per-process value; it is a routing hint, not a credential.

Native subscriptions share the upstream Pi account store at
`${PI_CODING_AGENT_DIR:-~/.pi/agent}/auth.json`. Run `pi auth login openai-codex`
or `pi auth login anthropic` once. The harness uses Pi's public `ModelRuntime`
for credential reads, refresh, and cross-process locking. It does not copy
tokens from Codex or Claude Code. Credential writes settle before a normal
harness shutdown.

## Limits

- **No sandbox for coding tools.** `read`, `write`, `edit`, and `bash` run with
  the invoking user's filesystem and network access. The code-mode QuickJS
  sandbox limits memory, not authority.
- **No permission gate.** There is no approval prompt and no tool allow-list.
  Use an outer sandbox or a throwaway worktree when that matters.
- **Restart semantics.** Pending tasks resume. A tool declared `replay:
  "unsafe"` (the `subagent` tool) is not rerun after a crash; the model sees an
  interrupted result and can check `subagent list`. Code-mode scripts replay from
  their journal.
- **MCP is best effort.** If `donsetch` or `graphify-mcp` cannot start, the
  harness logs the server name and reason and continues without that server.
  Servers start in the project directory.
- **One live owner.** Do not open the same database from two writers.
- **Subagent children** use `litellm/glm-5.3` by default and cannot start
  subagents of their own.

## Layout

- `src/providers.ts` — gateway providers and request-time key resolution.
- `src/harness.ts` — storage, registry, MCP bridge, default agent.
- `src/subagent.ts` — background subagent tool and tasks.
- `src/cli.ts` — the commands above.
- `test/` — offline tests with the faux provider and an in-memory MCP transport.
