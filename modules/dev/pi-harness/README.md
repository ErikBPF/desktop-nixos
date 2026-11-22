# pi-harness

A Pi-native, durable coding harness for the two home model gateways. It uses
`@earendil-works/pi-durable` for conversations, tasks, gates, restart recovery,
and code mode. It does not recreate OpenCode's permission engine, role servers,
ports, or backend wrapper.

## What it provides

- Two providers: `litellm` (Orion) and `work`, both on the OpenAI completions
  API, with `deepseek-v4.1-flash` and `glm-5.3-flash`. Costs and limits come from
  `modules/dev/opencode.nix`.
- Coding tools (`read`, `write`, `edit`, `bash`), image fitting, code mode
  (`createCodemodeExtension` with a 256 MiB QuickJS sandbox), tool search, one
  MCP extension per configured server with deferred tools, and background
  subagents.
- SQLite storage. Conversations survive restarts. `resume` continues pending
  tasks.
- The default agent runs in the project directory and uses that project's
  `AGENTS.md` as instructions.

## Run

```bash
npm install --ignore-scripts
npm run build
npm test

# from source
npx tsx src/cli.ts ask "List the top-level directories." --project /path/to/repo

# built CLI
nix build --file ./default.nix
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
- `--model <provider/id>` (`litellm` or `work`; default
  `litellm/deepseek-v4.1-flash`)
- `--thinking <level>` (`off`, `minimal`, `low`, `medium`, `high`, `xhigh`,
  `max`; default `high`)
- `--state-dir <dir>` — override the storage root
- `--no-mcp` — do not start the donsetch and graphify MCP servers

## Storage

`${XDG_STATE_HOME:-~/.local/state}/pi-harness/<project>.db`, where `<project>`
is the sanitized base name of the project directory. SQLite runs in WAL mode.
One process must write a database at a time; there is no cross-process locking.

## Credentials

Keys are resolved when a request is made, never at module load and never
printed:

1. `/run/secrets/opencode/litellm_key` and `/run/secrets/opencode/work_key`
2. `OPENCODE_LITELLM_KEY` and `OPENCODE_WORK_KEY`

LiteLLM also requires an `x-opencode-session` header. The harness sends a stable
per-process value; it is a routing hint, not a credential.

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
- **One live owner.** Do not open the same database from two writers.
- **Subagent children** use `litellm/glm-5.3-flash` by default and cannot start
  subagents of their own.

## Layout

- `src/providers.ts` — gateway providers and request-time key resolution.
- `src/harness.ts` — storage, registry, MCP bridge, default agent.
- `src/subagent.ts` — background subagent tool and tasks.
- `src/cli.ts` — the commands above.
- `test/` — offline tests with the faux provider and an in-memory MCP transport.
