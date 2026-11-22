# Declarative OpenCode V2

**Status:** Endeavour user environment activated; native backend identity/security checks passed; live provider/MCP acceptance is tracked in the [one-pager](../behaviors/opencode-v2-migration/one-pager.md).

`modules/dev/opencode.nix` owns shared Home Manager configuration, provider
policy, essential plugins and global CLI settings. It selects
`opencode-flake.homeManagerModules.withPackageV2`; the consumer's immutable
flake lock determines the installed binary. Package updates land and
publish in the leaf before updating this consumer. Never substitute a
sibling working tree during production builds or deployment.

## Explicit workspace backends

`modules/desktop/workspace-sessions.nix` declares Endeavour's two independent
foreground V2 servers. They do not register as the native shared CLI
service or replace the isolated trial controlling this task.

| Client | Backend | Loopback port | Default route |
|---|---|---|---|
| `ol` | `opencode-homelab.service` | 4096 | `litellm/deepseek-v4.1-flash` |
| `ow` | `opencode-dataplatform.service` | 4097 | `work/deepseek-v4.1-flash` |

Native clients use the exact packaged executable and explicit `--server`
URLs. `ol`/`ow` add `--auto`; the global default is auto-accept as well, so
every client approves `ask` rules without a human.
Routing is applied on the server, not guessed from the client's
directory. Only the selected gateway's sanctioned runtime key is sourced;
no administrator fallback is used. Direct Go and OpenAI remain separate
provider choices, subject to available credentials. Fresh database
namespaces do not imply that direct OAuth credentials were copied; use
`/connect` in the relevant client if authentication is required.

## Three-level agents

Both backends replace the default `build` agent with the repository's
three-level hierarchy: `pilot-l1` (plan and dispatch independent slices),
`pilot-l2` (slice coordinator) and `pilot-l3` (executor/reviewer). The
`three-level` plugin supplies `dispatch_slice` and `slice_status`; L2 model
selection comes from `OPENCODE_THREE_LEVEL_L2_MODEL`, which the backend
wrapper derives from the generated profile.

| Backend | L1 | L2 and L3 |
|---|---|---|
| `ol` | `litellm/deepseek-v4.1-flash#max` | `litellm/deepseek-v4.1-flash#high` |
| `ow` | `work/deepseek-v4.1-flash` | `work/deepseek-v4.1-flash` |

The work gateway's DeepSeek entry exposes no reasoning variants, so `ow`
carries no `#variant` suffix; the model definition still rejects
`reasoning_effort`. Each profile is injected inline through
`OPENCODE_CONFIG_CONTENT` (highest precedence) and
`OPENCODE_DISABLE_PROJECT_CONFIG=1` prevents a repository `opencode.json`
or `.opencode/opencode.json` from changing the managed role configuration.
Backend state uses the same OS file permissions as other user-owned files.

Every role runs shell, invokes native subagents and edits source. The global
`permissions` rules reach every agent; role lists only narrow `dispatch_slice`
and `slice_status` authority. L1 carries an explicit `shell allow *` and
`subagent allow *`. All roles inherit unrestricted read, edit and shell rules,
matching Pi coding-tool authority. Repository instructions still govern intent;
they are not an enforced tool sandbox.

`OPENCODE_DISABLE_PROJECT_CONFIG=1` also disables project `AGENTS.md`
discovery. Each generated profile therefore appends the workspace `AGENTS.md`
by absolute path; nested `AGENTS.md` files are not discovered by these
backends.

The generated profiles are exposed read-only as
`programs.opencode-backends.profiles` for tests; do not hand-edit a running
backend.

Each server has its own data, cache and state namespace. New databases are
`~/.local/share/opencode-v2-backends/{homelab,dataplatform}/opencode.db`.
Service UMask 0077 makes newly created state owner-only. Native server
passwords are generated into private state files and supplied to matching
clients without printing them. Authentication must be verified against
each explicit endpoint, including a negative control without credentials.

## Preserved V1 state and clients

V2 never uses the original
`~/.local/share/opencode/opencode-{homelab,dataplatform}.db` files.
History import is not part of this migration. The approved exception is
permission-only tightening of the existing homelab V1 database to 0600;
contents and schema remain unchanged. Keep a matching reachable recovery
generation/configuration, not merely an unrooted V1 executable path.

The Rust client targets V1 API contracts and is not part of this native V2
deployment. Source changes here do not migrate that independent project.
Existing tmux/Herdr sessions retain their keep-old behavior.

## Plugins and settings

Reuse the V2 RTK shell shim: it rewrites after approval of the original
command, rather than mutating tool input before permissions. The gateway
hook scopes `x-opencode-session` to the intended provider and actual
session. Plugin loading alone is not proof that either behavior works.

`modules/dev/agent-policy.md` is the single owner of Graphify guidance for OpenCode, Codex and Claude, so there is no OpenCode-only plugin.

One global `cli.json` owns terminal settings and permission prompts. Tabs are
off so tmux owns window switching; the global default is auto-accept, and
`ol`/`ow` pass `--auto` as well, so the permission prompt is never a gate.
Both stay inside their own repository (branch worktrees included) so the
personal/work split holds. It sets `session.permissions = "autoaccept"` and
`session.sidebar = "auto"`.
Supported compaction uses `keep.tokens`, not ignored `tail_turns`.
Application self-updates are disabled; package changes flow through Nix.
Coding-tool access matches the Pi harness: read, edit and shell actions are
allowed without harness prompts or path/command denials. The invoking user's
OS permissions remain the boundary; this does not grant root or change file
ownership. Secret files, backend state and commands that were previously denied
are accessible when the OS allows them. Reading credentials may expose values
to the configured model provider and persisted session history. Keep secrets
out of reports, commits and indexes; use them without printing when possible.
Provider routing and L1/L2/L3 dispatch boundaries remain separate controls.
The repository's direct-launch `opencode.json` uses the same coding authority.

`modules/dev/opencode.nix` packages every local MCP server as a Nix derivation
(`graphify`, `nix` via the `opencode-flake` default, and `donsetch` from its
release tarball). Nothing is resolved through `npx` at server start, so a
backend restart does not depend on the npm registry. Native file tools replace
the former unversioned filesystem MCP. The isolated trial's independent MCP
refresh work is not overwritten by normal-user activation.

[Session shortcuts and optional experiments](../guides/opencode-v2-sessions.md)
cover Context Fold and usage sidebar. Both are absent from default plugin
lists. DCP 3.2.0 has a V2 entrypoint, but reported automatic-tracking defects
mean it is not reintroduced without exact-version behavioral evidence.

## Verification and activation

Leaf validation builds the exact V2 package with
`nix build .#opencode-v2 --no-link`; full flake checks belong in CI.
Desktop focused checks live in `tests/opencode-profiles/`,
`tests/local-workspace-sessions/` and `tests/opencode-project/`.
Run owner lint, format, docs and touched-host dry-build gates before activation.

Use the evaluated candidate binary, not the older executable on PATH:

```sh
export OPENCODE_TEST_BINARY="$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.endeavour.config.home-manager.users.erik.programs.opencode.package \
  --builders '')/bin/opencode"
python3 -m unittest discover -s tests/opencode-profiles -p 'test_*.py'
python3 -m unittest discover -s tests/local-workspace-sessions
python3 -m unittest discover -s tests/opencode-project -p 'test_*.py'
```

For the approved Endeavour user-only activation, use:

```sh
just home-switch endeavour
```

The recipe sets normal XDG roots and runs activation in the independent
`home-manager-switch.service` user unit. It survives a backend restart and
rejects overlapping activations through that same unit name. Inspect its logs
with `journalctl --user -u home-manager-switch.service`. Do not invoke a
Home Manager activation script directly from an isolated harness environment.

After activation, verify both unit PIDs/executables, authenticated V2 API
responses, routes, model/tool behavior and V1 metadata. Native discovery can
start another service; it is not evidence for these explicit backends.
Deploy only Endeavour. Shared feature changes reach Orion, Apollo and
Pathfinder only through separately authorized host activation.
