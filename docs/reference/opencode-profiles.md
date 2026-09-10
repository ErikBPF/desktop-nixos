# Declarative OpenCode profiles

**Status:** Activated on Endeavour and Orion; Apollo verified. Pathfinder awaits
reachability. Latest rollout evidence: [desktop reconciliation](../reference/2026-09-07-desktop-reconciliation.md).

`modules/dev/opencode.nix` owns the shared Home Manager configuration, plugins,
provider policy and workflow commands. `modules/dev/_opencode-profiles.nix` owns
the gateway launchers. Home defaults to **DeepSeek V4.1 Flash** (`litellm/deepseek-flash`, via OpenCode Go); work defaults to **GLM 5.3 Flash**. Helper
agents inherit the selected gateway and model instead of carrying separate routes.

| Command | Gateway | Optional orchestration |
|---------|---------|------------------------|
| `opencode-home` | Home LiteLLM | None |
| `opencode-work` | Work proxy | None |
| `opencode-home-omo` | Home LiteLLM | Oh My OpenCode |
| `opencode-work-omo` | Work proxy | Oh My OpenCode |

The baseline loads RTK, Ponytail, `@tarquinen/opencode-dcp@3.1.15`, and a small
local gateway header hook. The hook forwards the real session ID as
`x-opencode-session`, required by Go-backed routes behind custom LiteLLM providers.
RTK itself is also installed declaratively; the plugin alone does not provide its
executable. OpenCode is pinned to the published 1.18.29 package.
Oh My OpenCode `5.0.0-beta.43` is explicit opt-in through the `-omo` launchers.
Memory, quota, ntfy and discovery plugins are outside the baseline. Their local
data remains available; this change does not migrate or delete it.

The launchers select a late `OPENCODE_CONFIG_DIR` overlay so project configuration
cannot accidentally replace the selected default model. `enabled_providers`
retains compatibility with OpenCode 1.18.29; the provider policy also records the
allowed gateway. Credentials continue to come from runtime environment values.
These are workflow profiles, not a security sandbox: repository configuration
and plugins remain trusted code. Separate credentials and provider-side controls
remain responsible for trust boundaries.

The inherited OpenCode module reaches **Endeavour and Pathfinder** through
`profile-desktop`, and **Orion and Apollo** through explicit imports. Activation
and verification must be recorded per host; a local source change does not deploy
all four. Discovery and the other headless hosts do not import this home module.

Endeavour recovery preserves both active JSON files and their existing `.backup`
files in a unique private archive before Home Manager resumes. Review the candidate
generation, move only the old backups out of the collision path, and let Home
Manager perform its normal backup and linking. Never use `force = true` or activate
the stale failed generation. Verify managed links and service success afterward;
clear the historical upgrade failure only after its Home Manager cause is resolved.

Verification: `node tests/opencode-profiles/test_headers.mjs` checks header
forwarding; `python3 -m unittest discover -s tests/opencode-profiles -v`
evaluates the profile helper and checks repository overrides with the installed
OpenCode binary. Profile files live under
`~/.config/opencode/profiles/{home,work,home-omo,work-omo}/`; OmO profiles also own
`tui.json`. Pinned beta.43 reads agent/category routes from named profiles in
`~/.omo/omo.jsonc`; launchers set `OMO_PROFILE` explicitly. The legacy
`oh-my-opencode.json` sidecar is only a migration input. Run dry-build gates before
activation and verify the installed commands afterward.
