# Three-level agents on the workspace backends

**Status:** Implemented and statically verified; host activation and live
model-inference acceptance pending.
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
- `node --test tests/opencode-profiles/test_three_level_dispatch.mjs` — 5 pass
  (dispatch, env model, variant-less pass-through, fail-closed, authorization).
- `python3 -m unittest discover -s tests/local-workspace-sessions` — wrapper
  contract updated for the inline profile, `--auto`, disabled project config
  and L2 model export.
- A disposable 2.0.27 server loaded the generated homelab profile and listed
  `pilot-l1`, `pilot-l2` and `pilot-l3` through `/api/agent`.
- Not yet observed: live model inference through each layer, `dispatch_slice`
  against a real provider, and host activation.

## Decisions

- Keep the unmerged pilot branch's `op` launcher out of scope; the framework is
  delivered through the workspace backends instead, so no launcher or trial
  configuration is required.
- Inline config over a custom config file: project config is merged after the
  custom file, which could override role permissions; inline wins and project
  config is disabled outright.
- The work gateway stays variant-less until its DeepSeek route is qualified
  with reasoning effort.

## Remaining work

Activate the Home Manager generation, restart both backends, confirm the live
`/api/agent` hierarchy and one dispatch per backend, then retire the isolated
trial client and its hand-written cleanup script.
