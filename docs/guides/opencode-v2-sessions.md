# OpenCode V2 sessions and optional plugins

**Status:** source-backed guide; backend migration and terminal-specific verification are tracked in the [migration page](../behaviors/opencode-v2-migration/one-pager.md).

## Native session management

`ol` and `ow` are intended to connect native V2 clients explicitly to the
homelab and dataplatform backends. Tabs belong to the connected backend;
they do not combine sessions from two different servers. Keep both clients
available when switching between home and work.

The default leader is **Ctrl+X**, released before the following key:

| Shortcut | Action |
|---|---|
| Ctrl+X, N | New session |
| Ctrl+X, L | Session list |
| Ctrl+O | Recent sessions and projects |
| Ctrl+1 … Ctrl+9; Ctrl+0 | Select tabs 1–10 |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous tab |
| Alt+Down / Alt+Up | Alternative next / previous tab |
| Alt+Shift+Down / Alt+Shift+Up | Next / previous unread tab |
| Ctrl+X, W | Close current tab |
| Ctrl+Shift+T | Reopen last closed tab |
| Ctrl+R | Rename session |
| Ctrl+B | Background blocking session tools |
| Escape | Interrupt session |
| Ctrl+X, C | Compact session |
| Ctrl+P | Command palette and settings |

Inside the diff viewer, Alt+Up/Down navigates files instead. Terminal or
tmux bindings can intercept Ctrl+Tab and Ctrl+number; the leader-number
alternatives and Alt bindings provide fallbacks. Verify delivery in the
actual terminal before changing bindings. Defaults above are documented,
not evidence that every terminal emits distinct key sequences.

V2 has one global `~/.config/opencode/cli.json`, managed through Home
Manager. Server/project config and legacy layered `tui.json` are not the
place for terminal bindings. Prefer native defaults over a navigation
plugin. Keep `session.permissions` set to `prompt`, never `autoaccept`.

Sources: [V2 keybinds](https://opencode.ai/v2/docs/cli/keybinds),
[CLI settings](https://opencode.ai/v2/docs/cli/config).

## Optional experiments, not default plugins

Both experiments are opt-in. The pinned enable-time fragments live under
`modules/dev/opencode-experiments/`, outside plugin/config discovery.
Apply enable-time changes to the owning
declarative OpenCode module and redeploy; do not modify managed live files
or run a global plugin installer over Home Manager configuration.

### Context Fold

The immutable candidate is
`github:GitMacke/opencode-context-fold#a8347566f996ed51d9d6d06f9f56ae88b6d1f5f4`
(tag `v0.1.1`). The [server configuration fragment](../../modules/dev/opencode-experiments/context-fold.json)
keeps debug disabled. Merge its plugin entry only for an approved experiment.

The plugin offers `fold`, `peek` and `unfold`; archives remain accessible
after summaries replace model-visible conversation. It does not rewrite
stored history. Activation begins on a subsequent eligible model request,
not the request that called `fold`. Its tagged dependencies target V2
2.0.3, so compatibility with our exact packaged version must be tested.

Folding invalidates the provider cache from the modified prefix. Measure
cached/uncached input and total cost, not just shorter context. Native
compaction checkpoints limit in-place unfolding. Do not stack DCP and
Fold until their combined transforms pass a bounded test.

**Privacy:** keep debug disabled. Debug mode writes full before/after
conversation dumps; archives also contain historical conversation data.
Use disposable non-sensitive sessions for trials.

Source: [pinned Context Fold release](https://github.com/GitMacke/opencode-context-fold/tree/v0.1.1).

### Usage sidebar

Candidate `opencode-plugin-usage@2.0.4` is a **CLI-only** plugin. It belongs
in global `cli.json`'s `plugins`, not server plugin discovery. It reads
provider credentials to query their usage endpoints, so review that access
before enabling it.

Supported direct providers include OpenCode Go and OpenAI/Codex. The
`litellm` and `work` aliases are not implemented. A fallback's direct
subscription quota is not gateway usage, spend or billing. OpenAI shows
Codex subscription quota, not Platform API credit. Do not enable a trial
that presents unrelated fallback quota as the active gateway's usage.

The [CLI fragment](../../modules/dev/opencode-experiments/usage-sidebar.json)
sets `default` to `none`. In pinned 2.0.4 this is a source-verified sentinel,
not a dedicated documented disable flag: no provider named `none` exists,
so unsupported aliases show `usage: no source for litellm` or `work` and
return before credential resolution or fetching. Empty string is unsafe:
the parser replaces it with the Go fallback. Recheck this control flow
when updating. Keep real direct-provider quota visible.

Source: [pinned usage sidebar release](https://github.com/lhw/opencode-plugin-usage/tree/v2.0.4).

## Validation and rollback

First validate the exact packaged V2 runtime, essential header/RTK hooks,
provider routes and MCP source-content return. Only then trial optional
plugins independently with synthetic conversations. No token-saving or
performance claim is established by README statements or plugin loading.

V1 backend databases are preserved separately; optional-plugin tests must
never use them. Remove an experiment's declarative plugin entry and
redeploy to disable it. Existing folds retain plugin storage; disabling
does not import, migrate or delete session history.
