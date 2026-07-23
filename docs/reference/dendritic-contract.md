# Dendritic module contract

**Status:** Reference (the rules `just structure-check` enforces).

This flake is **dendritic**: `flake.nix` is `flake-parts.mkFlake` + `import-tree
./modules`. Every `.nix` file under `modules/` is auto-imported as a flake-parts
module — there are no aggregator `default.nix` import lists. This note is the
short contract a new module file must follow; `just structure-check` checks the
mechanical parts.

## Rules

1. **Every imported file is a flake-parts module.** A file under `modules/` that
   `import-tree` picks up must evaluate as a flake-parts module (`{ ... }: { ... }`
   or `{ config, ... }: { ... }`), not a bare NixOS module.
2. **Reusable NixOS leaves register under `flake.modules.nixos.<name>`.**
3. **Reusable Home Manager leaves register under `flake.modules.home.<name>`.**
4. **Hosts register `configurations.nixos.<host>.module`** (see
   `modules/configurations.nix`). A host `default.nix` stays thin: an import
   list + genuinely host-specific config.
5. **Profiles are composition only** — `profile-base` / `profile-desktop` /
   `profile-server` import named leaves; they don't define features inline.
6. **Shared values flow through top-level options**, never `specialArgs`
   (`modules/meta.nix`, `modules/secrets.nix`).

## Naming

- Registry names are lowercase kebab-case.
- **Host-only** leaves are prefixed with the host: `<host>-<capability>`
  (`kepler-k3s-cluster`, `discovery-compose`). Known hosts: `pathfinder`,
  `discovery`, `laptop`, `orion`, `kepler`, `archinaut`.
- **Reusable** leaves use `<domain>-<capability>` or a bare capability
  (`home-manager-base`, `packages-shared`, `alloy`, `firewall`).
- **Profiles** use `profile-<role>`.
- Don't create per-host copies of a feature — parameterize one module (see
  `modules/services/syncthing-fleet.nix`).

## Private files (the `_` convention)

- `import-tree` **skips** any path whose segment starts with `_`. Such files are
  *not* auto-imported and must be imported explicitly (e.g. host hardware modules
  import `_hw-generated.nix`).
- A `_`-prefixed file **must not** register into `flake.modules.*` — it isn't
  scanned, so the registration would silently never happen. Helpers stay
  unregistered; promote to a named leaf if they grow options or multiple
  consumers.
- Generated/captured hardware state lives in `_hw-generated.nix` and should read
  as generated — never hand-edit it as if it were authored policy.

## Gotchas

- **New files must be `git add`ed before any `nix` command sees them** — flake
  eval ignores untracked files; the error is a misleading "attribute missing".
- Large files (>400 lines) are flagged by `structure-check` as candidate domains
  to split — a report, not a failure. Split only when a file hides multiple
  independently-reviewable surfaces (see
  [`../implemented/2026-06-24-repo-structure-improvements.md`](../implemented/2026-06-24-repo-structure-improvements.md) §10).

## Verify

`just structure-check` reports registration, naming, and size hygiene. It is
report-only for size/header findings and fails only on hard violations
(duplicate registered names, a `_`-prefixed file that registers).
