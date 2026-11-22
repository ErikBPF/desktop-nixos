# Pi shadow harness — S0 and plugin ports

**Status:** Implemented (not activated)

## Outcome

desktop-nixos pins `earendil-works/pi` v1.6.0 as a flake input, installs the
`pi` package through `m.home.pi`, and imports that module from
`profile-desktop` right after `m.home.opencode`. Pi sits beside OpenCode as a
shadow; OpenCode stays the default harness.

The owner narrowed this slice to instructions, model credentials, plugins and
MCP servers. Pi has no permission system, so the earlier `permission-gate.js`
port is removed. The accepted risk is recorded in
`homelab/docs/proposals/2026-11-22-pi-shadow-harness.md`.

The module writes these user-level files under `~/.pi/agent/`:

| File | Purpose |
| --- | --- |
| `settings.json` | codemode/grep/find/ls enabled, telemetry off, project trust `never`, ponytail npm package pinned |
| `models.json` | `litellm` and `work` providers with two flash models and complete cost objects |
| `mcp.json` | donsetch and graphify MCP servers from the same derivations OpenCode uses |
| `extensions/rtk.js` | replaces the built-in bash tool and rewrites commands with `rtk rewrite` |
| `extensions/session-header.js` | sets `x-opencode-session` for `litellm` and `work` |

No host was activated and no provider request ran. No secret value was read:
`models.json` names the runtime key paths inside `!cat` expressions.

## Commands and results

### Flake input and package build

The input commits to release tag `v1.6.0` at rev
`faac585884ae2c013a6b1400f3e9e77f10b34bac` and keeps its own `nixpkgs`
(no `follows`), matching the herdr input.

```
$ nix eval --impure --raw --expr '(builtins.getFlake "$PWD").inputs.pi.packages.x86_64-linux.pi.name'
pi-1.6.0

$ nix build --impure --no-link --print-out-paths --expr \
    '(builtins.getFlake "$PWD").inputs.pi.packages.x86_64-linux.pi'
/nix/store/qzm5v95n3c57qqgcx67glaib49znvmmp-pi-1.6.0
```

### Extensions

```
$ node --check modules/dev/pi-extensions/rtk.js
$ node --check modules/dev/pi-extensions/rtk.test.js
$ node --check modules/dev/pi-extensions/session-header.js
$ node modules/dev/pi-extensions/rtk.test.js
ok - rtk rewrite fallback checks
```

`rtk.test.js` registers a stub for `@earendil-works/pi-coding-agent` through
`node:module` `registerHooks`, imports the real `rtk.js`, and asserts four
paths: rtk missing, rewrite succeeds, non-zero exit, empty output.

`session-header.js` was checked against the v1.6.0 extension docs:
`before_provider_headers` mutates `event.headers`, the provider comes from
`ctx.model.provider`, and the session id comes from
`ctx.sessionManager.getSessionId()`.

### Schema validation

Both emitted JSON documents were evaluated out of the module and validated
against the published schemas with a throwaway Node script under `/tmp` (no
new repository dependency):

```
$ node /tmp/validate-pi-json.mjs
settings: PASS
models: PASS
control: PASS (missing cacheWrite rejected)
```

The control deletes `cacheWrite` from one model and asserts the validator
rejects it, so the passing result is not vacuous.

### Model catalog

The built binary lists both providers and all four models. `HOME` pointed at a
temporary directory with the emitted files and a dummy key value, so the run
read no secret:

```
$ HOME=$TMP pi --list-models
provider  model                context  max-out  thinking  images
litellm   deepseek-v4.1-flash  1M       384K     yes       yes
litellm   glm-5.3-flash        1M       131.1K   yes       no
work      deepseek-v4.1-flash  1.0M     393.2K   no        yes
work      glm-5.3-flash        1.0M     131.1K   no        no
```

The first attempt used `"$PI_TEST_KEY"` without setting the variable and Pi
silently listed no models. A provider whose key expression does not resolve is
dropped from the catalog; it is not reported as an error. The configured
`!cat` expressions are unaffected but were not exercised.

The configured package pin resolves and installs from npm:

```
$ HOME=$TMP pi list
added 1 package in 797ms
User packages:
  npm:@dietrichgebert/ponytail@4.8.4
    /tmp/.../.pi/agent/npm/node_modules/@dietrichgebert/ponytail
```

### Static gates

```
$ just lint        # exit 0
$ just fmt-check   # exit 0
$ just docs-check  # exit 0
```

### Diff and untouched files

```
$ git diff --stat HEAD
 docs/audits/2026-11-22-pi-shadow-slice.md         | ...
 modules/dev/pi-extensions/package.json            |   1 +
 modules/dev/pi-extensions/rtk.js                  |  31 ++
 modules/dev/pi-extensions/rtk.test.js             |  50 ++
 modules/dev/pi-extensions/session-header.js       |  16 +
 modules/dev/pi.nix                                | ...
 modules/profiles/desktop.nix                      |   1 +
```

`modules/dev/opencode.nix`, `modules/desktop/workspace-sessions.nix` and
`modules/dev/opencode-plugins-v2/*` are unchanged (`git diff --quiet` exits 0).
`modules/dev/pi-extensions/permission-gate.js` and its test are deleted.

## Decisions

- **No permission port.** `permission-gate.js` and `permission-gate.test.js`
  are deleted, and `pi.nix` no longer wires them. Pi has no approval step, and
  the owner accepted the exposure for manual use in a task worktree.
- **Cost objects are complete.** Every model carries `input`, `output`,
  `cacheRead` and `cacheWrite`, as `models.schema.json` requires. Values keep
  the OpenCode facts; an unknown value is `0`, never an invented price. This
  adds `cacheWrite: 0` everywhere and `cacheRead: 0` for the two entries that
  omitted it (LiteLLM GLM and Work DeepSeek).
- **Ponytail is a package.** Upstream 4.8.4 ships a native Pi extension through
  its `package.json` `pi` field, so `settings.json` pins
  `npm:@dietrichgebert/ponytail@4.8.4` exactly. The OpenCode v2 adapter is not
  reused, and `extensions` stays empty because the package supplies its own.
- **rtk rewrites in a spawn hook.** `rtk.js` builds
  `createBashTool(process.cwd(), {spawnHook})` and registers it as `bash`, which
  replaces the built-in. The hook runs `execFileSync("rtk", ["rewrite", command],
  {timeout: 2000})` and returns `{command, cwd, env}` with `env` unchanged. A
  non-zero exit, an empty result or any thrown error returns the original
  command. No shell-shim indirection: there is no approval step for the shim to
  bypass.
- **Header hook kept as written.** The event name, provider source and session
  source match the pinned docs; no change was needed.
- **JSON as literal text.** `settings.json`, `models.json` and `mcp.json` stay
  literal `home.file.*.text` so the emitted bytes match the schemas exactly.
  `mcp.json` interpolates the two store paths.
- **Duplicated derivations.** `graphify` and `donsetch` remain copied from
  `modules/dev/opencode.nix`, with the in-file sync comment. This slice may not
  edit that file.
- **`pi` is the durable harness.** `m.home.pi` installs `pi-harness` and a `pi`
  symlink to it; the upstream shadow agent is renamed to `pi-agent`. Its
  `~/.pi/agent` configuration is unchanged and still belongs to the upstream
  agent.

## Gaps

- `graphify`/`donsetch` duplication needs extraction once
  `modules/dev/opencode.nix` is allowed to change.
- No live provider request ran, so the session header and the Work
  `supportsReasoningEffort: false` behaviour are unverified against the
  gateways.
- Extensions were checked with `node --check`, one assert test, and a binary
  start. No live Pi session exercised the rtk override or the ponytail
  extension.
- A provider with an unresolved key expression is silently absent from
  `--list-models`. The configured `!cat` paths were not read in this slice.
- The Home Manager symlinks make `mcp.json`/`settings.json` read-only; Pi fails
  to persist in-app edits. The files stay declarative.

## Rollback

Revert the branch commits. The `pi` input disappears with `flake.nix`; no
`nix flake update` is needed. The `~/.pi/agent` links disappear on the next
Home Manager activation. No host was switched, so no host rollback is needed.
