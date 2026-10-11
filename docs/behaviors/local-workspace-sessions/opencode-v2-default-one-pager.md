# OpenCode v2 as the default: migration receipt

**Stage / revision:** GREEN / E2E / 2
**Status:** Deployed and runtime-verified on Endeavour; fleet rollout to Orion, Apollo and Pathfinder pending
**Owner / date:** desktop-nixos + opencode-flake / 2026-10-11
**Basis:** User seed — "change my `ol` and `ow` implementations to use opencode
v2. Make it my default. We can remove v1. It can use the default alias."
Chosen packaging path: adopt v2 through `opencode-flake`, publish to FlakeHub,
bump the desktop-nixos input, then wire. Authorised: apply and run the Home
Manager switch on Endeavour.

## Outcome and why it matters

`opencode` on Endeavour is now the packaged v2 binary (`2.0.21`);
`ol`/`ow` open it at the homelab and dataplatform checkouts through the
default alias instead of v1 profile launchers and per-project serve backends.
One config, one binary, one background service.

## What changed

- **opencode-flake** `#54` (squash → `main` `2a26730`): `packages.opencode-v2`
  (official v2 Linux x64 npm release, `autoPatchelf` only, `installCheck`
  `--version`) exposed as `homeManagerModules.withPackageV2`.
- **desktop-nixos** (`feat/opencode-v2-default`): `modules/dev/opencode.nix`
  imports `withPackageV2`, drops `_opencode-profiles.nix`, and replaces the v1
  `plugin` list with a v2 `plugins` list (RTK shim, gateway headers,
  hash-pinned ponytail v2) sourced from `modules/dev/opencode-plugins-v2/`.
  `modules/desktop/workspace-sessions.nix` loses the two v1 serve backends and
  rewrites `ol`/`ow` as `opencode <directory>`. v1 profile/plugin tests are
  replaced by v2 equivalents; retired rollout recipes and the v1 backend test
  are removed. `flake.lock` pins `opencode-flake`
  `0.1.53+rev-2a2673015374`.

## Evidence and limits

| Check | Result |
|---|---|
| PR #54 checks (`check`, `package-build`) and FlakeHub publish + verify | Green |
| `nix flake update opencode-flake` | Lock at `0.1.53+rev-2a2673015374` |
| `nix eval …programs.opencode.package.outPath` | `…-opencode-v2-2.0.21` |
| `just dry endeavour` | Pass after prepending `/run/wrappers/bin` to PATH |
| `opencode --version` | `v2.0.21` |
| `ol` / `ow` source | `exec …/.nix-profile/bin/opencode <dir> "$@"` |
| `opencode-home` / `-work` / `-omo` | Absent from the profile |
| `~/.config/opencode/opencode.json` `plugins` + `model` | Three v2 paths (all present); `litellm/deepseek-v4.1-flash` |
| `opencode models` | Lists the LiteLLM providers/models |
| Hyprland | 24 clients, monitor `eDP-1` active |

## Decisions and corrections

- Use the default alias rather than a v2-named wrapper; `ol`/`ow` differ only by
  directory. Drop per-project serve backends — v2 manages one background
  service.
- Port only the behaviour-carrying plugins (RTK, gateway headers, ponytail);
  DCP has no v2 adapter.
- The local `d8dd7f4` "fix(mcp)" commit was a duplicate of upstream `#51`; the
  branch was rebased onto `origin/main` and does not ship it.
- **Interrupted first activation.** The first `just home-switch` was cancelled
  by a harness server restart while Home Manager was in `reloadSystemd`, after
  it had stopped `desktop-tmux.service`, `desktop-window-l1..l8`, `quickshell`,
  `hypridle` and `tray.target`. A second, complete `just home-switch` activated
  and restarted those units.
- **Stray imperative profile entry.** `nix profile list` held a manually
  installed top-level `opencode` (`opencode-1.18.30`) beside
  `home-manager-path`; it shadowed the HM-provided v2 binary. Removed with
  `nix profile remove --profile ~/.nix-profile opencode`. This entry is not
  managed declaratively — a future manual `nix profile install` of opencode
  would reintroduce the shadow.

## What continues / what waits

1. Roll Orion, Apollo and Pathfinder out separately and record per-host
   evidence (they pick v2 up on their next Home Manager activation).
2. Land the desktop-nixos branch as a PR (not yet pushed).
3. Optional: port `programs.opencode-tui` to the v2 server API.

## Risks and recovery

v1 and v2 share `~/.config/opencode/` and `~/.local/share/opencode/`. The
pre-switch DBs and credentials are backed up at
`~/.local/share/opencode-backup-pre-v2-20261011154956` (1.4 GiB);
`opencode.db` and the per-project DBs were untouched by the switch. Rollback:
re-pin the previous `opencode-flake` revision and re-run the Home Manager
recipe. `programs.opencode-tui` remains installed but targets the v1
`opencode serve` REST/SSE API, which v2 changed — use v2's built-in TUI.
