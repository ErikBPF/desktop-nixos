# Codex flake — global profile module

**Status:** Draft RFC, ready for first implementation spike. **Date:** 2026-06-29.
**Scope:** a new sister repo, `codex-flake`, modeled after `hermes-flake`.
It exports a Home Manager module for Codex global instructions and optional
config, then `desktop-nixos` consumes it as a flake input.

## Why

Current local module proves the user need:

- `~/.codex/AGENTS.md` is loaded by new Codex sessions.
- `@/home/erik/.codex/RTK.md` was **not** expanded into model context.
- Inline RTK guidance was loaded and changed behavior: fresh Codex used
  `rtk git status --short`.
- Declaratively managing `~/.codex/config.toml` was too heavy: Codex config is
  mutable and auth-adjacent, while `auth.json`, sessions, history, cache, and
  state DBs live in the same directory.

This should be factored out of `desktop-nixos` only if it becomes reusable:
global instruction rendering, RTK guidance, style guidance, and cautious optional
config generation. Host-specific defaults stay in the consuming repo.

## Reference search

No reusable flake/project found. GitHub code search found personal dotfiles:

- `futile/nixos-config` — Home Manager links `~/.codex/AGENTS.md` and optional
  `~/.codex/config.toml`.
- `fdietze/dotfiles` — one shared `AGENTS.md` linked into Claude, Codex,
  opencode, and other agents.
- `hikuohiku/dots-nix` — installs `pkgs.codex`, links global `AGENTS.md`, and
  shares a skills tree.
- `joshsymonds/nix-config` — manages `~/.codex/config.toml` and explicitly notes
  Codex UI cannot save changes to a Nix-store symlink.

Searches for `homeManagerModules` + Codex, `programs.codex` + `mkEnableOption`,
and Codex-specific flake repos came back empty. The gap appears to be a reusable
module, not a novel dotfile trick.

## Hermes-flake pattern to copy

`hermes-flake` is the model:

- `flake-parts` project with `systems`, `formatter`, `checks`, `devShell`.
- `homeManagerModules.default` plus a named alias.
- Optional packages/apps/templates where they add real value.
- Consumer wrapper in `desktop-nixos` imports the upstream module and sets
  site-specific policy.
- Checks prove rendering and module evaluation, not live external service calls.

Codex does **not** need the NixOS/container half at first. Codex is a user CLI
with mutable user state, so Home Manager is the correct first API boundary.

## Proposed flake API

```nix
{
  programs.codex-profile = {
    enable = true;

    package.enable = true;
    package.package = pkgs.codex;

    agents.enable = true;
    agents.preamble = ''
      # Codex Defaults
    '';
    agents.extraText = "";

    rtk.enable = true;
    rtk.inline = true;
    rtk.mode = "prefer-readonly";

    style.enable = true;
    style.name = "caveman";
    style.level = "full";
    style.text = "";

    rtkFile.enable = true;

    config.enable = false;
    config.settings = {};
  };
}
```

Rendered files:

- `~/.codex/AGENTS.md` when `agents.enable = true`.
- `~/.codex/RTK.md` when `rtkFile.enable = true`.
- `~/.codex/config.toml` only when `config.enable = true`.

Defaults:

- RTK is **inline** in `AGENTS.md`; no `@` include dependency.
- RTK wording is scoped: prefer for read-only/high-output commands; raw commands
  for side effects, quoting, redirection, sandboxing, approval prompts, or exact
  shell semantics.
- `config.enable = false` to avoid overwriting mutable Codex config by accident.
- No auth/session/cache/history/state file management.

## Grilled decisions

### D1 — Separate flake or keep local?

**Decision:** separate flake only after the local module stays stable for one
more iteration.

**Reason:** `hermes-flake` is worthwhile because it packages a real upstream
application plus NixOS deployment surfaces. Codex-profile starts as text
rendering. Extract when its API is clean enough that another user can consume it.

### D2 — Manage `config.toml` by default?

**Decision:** no.

**Reason:** public dotfiles do this, but it blocks Codex UI writes and sits next
to auth/session state. Make it opt-in, typed, and documented as declarative-only.

### D3 — Use RTK upstream `@RTK.md` include?

**Decision:** no for default behavior.

**Reason:** this session proved the include text can be present while not
expanded. The flake may still emit `RTK.md` for humans/tooling, but loaded
behavior must be inline in `AGENTS.md`.

### D4 — Copy `rtk init -g --codex` verbatim?

**Decision:** no.

**Reason:** current RTK generated text says "Always prefix shell commands with
`rtk`". That is too broad for state-changing commands and shell edge cases. The
flake should carry safer Codex-specific wording.

### D5 — Install `rtk`?

**Decision:** not in v1.

**Reason:** RTK is not in nixpkgs here and may be installed by another channel.
Instruction rendering should not hide package provenance. Add an optional package
later if we pin upstream release hashes like `discovery-hermes-oci` does.

### D6 — Name `programs.codex`?

**Decision:** avoid it for now; use `programs.codex-profile`.

**Reason:** Home Manager may eventually grow an official `programs.codex`.
Squatting the obvious name creates future migration pain. A profile module can
later be folded into or renamed around an official module.

## First implementation spike

1. Create `~/Documents/erik/codex-flake`.
2. Scaffold like `hermes-flake`: `flake.nix`, `modules/home-manager.nix`,
   `checks.nix`, `README.md`, `Justfile`, `templates/default`.
3. Add checks:
   - Home Manager module evaluates.
   - rendered `AGENTS.md` contains RTK inline and caveman text.
   - `config.enable = false` does not create `.codex/config.toml`.
   - opt-in `config.settings` renders TOML.
4. Add `desktop-nixos` input:
   `codex-flake.url = "github:ErikBPF/codex-flake"; inputs.nixpkgs.follows = "nixpkgs";`
5. Replace local `modules/dev/codex.nix` text rendering with:
   `imports = [inputs.codex-flake.homeManagerModules.default];`
   plus local policy under `programs.codex-profile`.
6. Verify with:
   - `just fmt-check`
   - `nix flake check ~/Documents/erik/codex-flake`
   - `just build laptop`
   - fresh `codex exec` probes for inline RTK + caveman + `rtk git status --short`.

## Rejected shortcuts

- **Only keep `desktop-nixos` local:** simplest today, but every future agent
  profile tweak remains tangled with host config.
- **Shell out to `rtk init -g --codex` in activation:** imperative, not
  reproducible, mutates files Home Manager should own, and restores unsafe
  wording.
- **Manage whole `~/.codex`:** unsafe. It contains auth, logs, session DBs,
  cache, shell snapshots, and mutable app state.
- **Force `config.toml`:** convenient for one user, hostile as reusable default.

## Open question

Whether the first external repo should be called `codex-flake` or a broader
`agent-profile-flake`. Recommendation: `codex-flake` first. The Codex file
layout and behavior probes are specific enough that a generic agent framework
would dilute the first version.
