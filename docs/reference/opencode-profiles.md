# Declarative OpenCode V2

**Status:** two-backend migration candidate; published leaf pinned, local verification passed; Endeavour activation is tracked in the [one-pager](../behaviors/opencode-v2-migration/one-pager.md).

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
URLs. Routing is applied on the server, not guessed from the client's
directory. Only the selected gateway's sanctioned runtime key is sourced;
no administrator fallback is used. Direct Go and OpenAI remain separate
provider choices, subject to available credentials. Fresh database
namespaces do not imply that direct OAuth credentials were copied; use
`/connect` in the relevant client if authentication is required.

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

One global `cli.json` owns terminal settings, permission prompts and native
tabs. Supported compaction uses `keep.tokens`, not ignored `tail_turns`.
Application self-updates are disabled; package changes flow through Nix.
Global permission checks protect direct secret reads and ask before shell
commands outside narrow inspection allowances. Shell is not a sandbox;
authorized deployment still needs approval rather than a permanent deny.

The project config inherits the packaged Nix MCP. Native file tools replace
the former unversioned filesystem MCP. The isolated trial's independent
MCP refresh work is not overwritten by normal-user activation.

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

For the approved Endeavour user-only activation, use the documented recipe
with normal roots, not the harness's isolated trial XDG roots:

```sh
XDG_CONFIG_HOME="$HOME/.config" \
XDG_DATA_HOME="$HOME/.local/share" \
XDG_STATE_HOME="$HOME/.local/state" \
XDG_CACHE_HOME="$HOME/.cache" \
just home-switch endeavour
```

After activation, verify both unit PIDs/executables, authenticated V2 API
responses, routes, model/tool behavior and V1 metadata. Native discovery can
start another service; it is not evidence for these explicit backends.
Deploy only Endeavour. Shared feature changes reach Orion, Apollo and
Pathfinder only through separately authorized host activation.
