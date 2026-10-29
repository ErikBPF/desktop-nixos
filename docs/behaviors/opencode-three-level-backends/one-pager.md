# Three-level agents on the workspace backends

**Status:** Activated on Endeavour; live agent hierarchy verified. Model
inference and a real `dispatch_slice` run remain unverified.
**Checkout:** `worktrees/opencode-three-level-backends-20261026`, branch
`feat/opencode-three-level-backends`.
**Seed:** "lets use 3-layer on ol and ow. on ol use deepseek 4.1 flash next on
max thinking for planner and high for both layers 2 and 3. Lets allow auto on
both. turn sidebar on. Lets focus on declarative stack. If it is not on our repos
it shoudlnt exist. In the end do a /rv"

## Outcome

`ol` and `ow` now serve the repository's three-level hierarchy instead of the
plain `build` agent. Homelab runs `litellm/deepseek-v4.1-flash#max` for L1 and
`#high` for L2/L3. Dataplatform runs `work/deepseek-v4.1-flash` without a
variant because that gateway's model exposes none and its route rejects
`reasoning_effort`.

Auto-accept is scoped: the `ol`/`ow` clients pass `--auto`, while the shared
`cli.json` stays `prompt`. `session.sidebar` is `auto` (the only non-hidden
schema value).

L1 carries an explicit `shell: ask` rule so it can validate credentials and
write documentation; `edit` stays denied outside `docs/*`, and protected
destructive commands stay denied, so implementation still goes through L2/L3.

## Changes

- `modules/desktop/workspace-sessions.nix` generates one profile per backend:
  agents, models, provider policy, plugins, skills and a read/edit deny on the
  backend state root that holds the server password. Profiles are injected
  inline via `OPENCODE_CONFIG_CONTENT`; `OPENCODE_DISABLE_PROJECT_CONFIG=1`
  stops a repository config from widening role permissions. L2's model is
  exported as `OPENCODE_THREE_LEVEL_L2_MODEL`.
- `modules/dev/opencode-plugins-v2/three-level/` ports the plugin from the
  unmerged pilot branch and replaces its hardcoded OpenAI L2 model with the
  environment value, failing closed when unset or malformed.
- `modules/dev/opencode.nix` sets the sidebar and keeps global prompts; a
  previous commit disables builtin websearch so donsetch is the only search
  path.
- Tests: `test_three_level_backends.py`, `test_three_level_dispatch.mjs`,
  updated `test_settings.py` and the local-workspace wrapper contract.
- CI runs the node dispatch test in the OpenCode gateway profile job.

## Evidence

- `python3 -m unittest discover -s tests/opencode-profiles -p 'test_*.py'` —
  17 pass, including 7 backend-profile assertions and the settings contract.
- `node --test tests/opencode-profiles/test_three_level_dispatch.mjs` — 6 pass
  (dispatch, env model, variant-less pass-through, fail-closed, malformed input,
  authorization).
- `python3 -m unittest discover -s tests/local-workspace-sessions -p 'test_*.py'`
  — 29 pass; wrapper contract covers the inline profile, `--auto`, disabled
  project config, L2 model export and backend password retention.
- `just home-switch endeavour` activated the generation; both units restarted.
- Live `/api/agent` on 4096 and 4097 lists `pilot-l1`, `pilot-l2`, `pilot-l3`;
  homelab reports `#max`/`#high`/`#high`, dataplatform reports no variants.
  Both backends log donsetch, nix and graphify MCP connections; the
  `three-level` plugin is active.
- The generated homelab profile loaded in a disposable 2.0.27 server with a
  hostile project `opencode.json`; `pilot-l1` then resolved shell/edit to
  `deny`. The role now carries an explicit `shell: ask` rule, unit-tested
  alongside the protected destructive denies, and
  `OPENCODE_DISABLE_PROJECT_CONFIG=1` still removes the project rules.
- Not yet observed: live model inference through each layer and a real
  `dispatch_slice` against either provider.

## Decisions

- Keep the unmerged pilot branch's `op` launcher out of scope; the framework is
  delivered through the workspace backends instead. The stale manually installed
  `~/.local/bin/op` link and the hand-written `opencode-v2` wrapper were removed.
- Inline config over a custom config file: project config is merged after the
  custom file and could override role permissions; inline wins and project
  config is disabled outright.
- The work gateway stays variant-less until its DeepSeek route is qualified
  with reasoning effort; its existing model definition rejects
  `reasoning_effort`.

## Remaining work

Quit the isolated trial client, then remove
`~/.local/share/opencode-v2` and the hand-written
`~/.local/bin/cleanup-opencode-v2-trial`; the running review session still owns
that directory. Smoke-test one inference per backend and one `dispatch_slice`.

