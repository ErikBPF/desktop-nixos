# OpenCode v2 as the default: migration receipt

**Stage / revision:** GREEN (source + package build) / v2 default / 1
**Status:** Source complete and evaluated; deployment blocked on the FlakeHub publish of the packaged v2 binary
**Owner / date:** desktop-nixos + opencode-flake / 2026-10-11
**Basis:** User seed — "change my `ol` and `ow` implementations to use opencode
v2. Make it my default. We can remove v1. It can use the default alias."
Chosen packaging path: adopt v2 through `opencode-flake`, publish to FlakeHub,
bump the desktop-nixos input, then wire. Authorised: apply and run the Home
Manager switch on Endeavour.

## Outcome and why it matters

`opencode` is now the packaged v2 binary on every host that imports
`m.home.opencode`; `ol`/`ow` open v2 at the homelab and dataplatform
checkouts through the default alias instead of v1 profile launchers and
per-project serve backends. One config, one binary, one service model.

## What changed

- **opencode-flake** (`feat/opencode-v2`, commit `e995166`): new
  `packages/opencode-v2` (official v2 Linux x64 npm release, `autoPatchelf`
  only, install-check `--version`), exposed with
  `homeManagerModules.withPackageV2`. `just check` (eval) passes; the package
  builds to a store path and reports `2.0.21`.
- **desktop-nixos** (`feat/opencode-v2-default`): `modules/dev/opencode.nix`
  imports `withPackageV2`, drops `_opencode-profiles.nix`, and replaces the v1
  `plugin` list with a v2 `plugins` list (RTK shim, gateway headers,
  hash-pinned ponytail v2). The three v2 plugin sources live under
  `modules/dev/opencode-plugins-v2/`. `modules/desktop/workspace-sessions.nix`
  loses the two v1 serve backends and rewrites `ol`/`ow` as
  `opencode <directory>`. The v1 profile/plugin tests are replaced by v2
  equivalents; the retired rollout recipes and v1 backend test are removed.

## Evidence and limits

| Check | Result |
|---|---|
| `nix build .#opencode-v2` (opencode-flake) | Builds; `--version` = `2.0.21`; `installCheck` passes with a writable HOME |
| `nix flake check --no-build` (opencode-flake) | All checks pass |
| `alejandra --check` (both repos) | Pass |
| `nix eval ...programs.opencode.package.version` (Endeavour, input overridden to the branch) | `2.0.21` |
| `nix eval ...programs.opencode.settings` | `plugins` = RTK + gateway-headers + ponytail-v2 store paths; `model` unchanged |
| `just dry endeavour` / `just home-switch endeavour` | **Not run** — the lock still pins the v1 `opencode-flake` revision |

## Decisions and corrections

Use the default alias rather than a v2-named wrapper: `ol`/`ow` differ only by
directory. Drop per-project serve backends because v2 manages one background
service. Port only the plugins that carry behaviour (RTK, gateway headers,
ponytail); DCP has no v2 adapter and was removed. The v1 `d8dd7f4` "fix(mcp)"
commit on the local main was a duplicate of upstream `#51`, so the branch was
rebased onto `origin/main` (`9cddc71`) and does not ship it.

## What continues / what waits

1. Push `feat/opencode-v2` and merge to `opencode-flake` main; wait for the
   FlakeHub publish.
2. `nix flake update opencode-flake` in desktop-nixos; then `just dry endeavour`
   and `just home-switch endeavour`.
3. Before the first v2 run on Endeavour, back up `~/.local/share/opencode`
   (v1 session database) and stop the v1 backends on ports 4096/4097.
4. Roll Orion, Apollo and Pathfinder out separately and record per-host
   evidence.

## Risks and recovery

v1 and v2 share `~/.config/opencode/` and `~/.local/share/opencode/`; the
first v2 run opens the existing v1 session database. Take the backup above
first. `programs.opencode-tui` stays enabled but targets the v1 `opencode
serve` REST/SSE API, which v2 changed; the client is unusable against v2 until
its own port lands — use v2's built-in TUI meanwhile. Rollback: keep the branch
unmerged; the switch is reverted by re-pinning the previous `opencode-flake`
revision and re-running the Home Manager recipe.
