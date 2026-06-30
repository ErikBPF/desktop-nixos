# Codex flake — global profile module

**Status:** ✅ Implemented (2026-06-30). **Date:** 2026-06-29.
**Scope:** a new sister repo, `codex-flake`, modeled after `hermes-flake`.
It exports a Home Manager module for Codex global instructions and optional
config, then `desktop-nixos` consumes it as a flake input.

## Implemented state

Shipped artifacts:

- Sister repo: `git@github.com:ErikBPF/codex-flake.git`.
- Current release: FlakeHub `https://flakehub.com/f/ErikBPF/codex-flake/*`.
- Published revision: `dde0da8f3b4693a4dbba9716386c7db2862ac6db`
  (`0.2.4+rev-dde0da8...`).
- Desktop integration: `desktop-nixos` commit `a1e8fe1 feat(codex): adopt
  codex-flake + opencode client on laptop`.
- Consumer input: `codex-flake.url =
  "https://flakehub.com/f/ErikBPF/codex-flake/*"` with `flake-parts`,
  `home-manager`, and `nixpkgs` following this repo's inputs.
- Home Manager wrapper: `modules/dev/codex.nix` imports
  `inputs.codex-flake.homeManagerModules.default` and enables package install,
  inline RTK guidance, and caveman full style.

Verified on 2026-06-30:

- `codex-flake`: `nix flake check --print-build-logs` passed.
- `codex-flake` GitHub Actions run `28416216970` passed, including
  `flakehub-publish` and `flakehub-verify`.
- FlakeHub wildcard resolves to revision
  `dde0da8f3b4693a4dbba9716386c7db2862ac6db`.
- `desktop-nixos`: `just fmt-check`, `just docs-check`, and
  `just build laptop` passed.
- Activated laptop toplevel:
  `/nix/store/cr40pddwwln1jwp6s1cwsgm505xh528m-nixos-system-laptop-26.11.20260616.567a49d`.
- Deployed files:
  - `~/.codex/AGENTS.md` is a Home Manager symlink and contains inline RTK +
    caveman full style.
  - `~/.codex/RTK.md` is a Home Manager symlink.
  - `~/.codex/config.toml` is absent by default.

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

## Implemented flake API

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

    configFile.enable = false;
    configFile.settings = {};
  };
}
```

Rendered files:

- `~/.codex/AGENTS.md` when `agents.enable = true`.
- `~/.codex/RTK.md` when `rtkFile.enable = true`.
- `~/.codex/config.toml` only when `configFile.enable = true`.

Defaults:

- RTK is **inline** in `AGENTS.md`; no `@` include dependency.
- RTK wording is scoped: prefer for read-only/high-output commands; raw commands
  for side effects, quoting, redirection, sandboxing, approval prompts, or exact
  shell semantics.
- `configFile.enable = false` to avoid overwriting mutable Codex config by
  accident.
- No auth/session/cache/history/state file management.
- `package.enable = false` in the reusable module by default; consumers opt in
  when they want this flake to install Codex itself.
- `rtk.source = "reduced"` by default, with `rtk.source = "generated"` available
  as an opt-in that runs `rtk init -g --codex --show` from a caller-provided RTK
  package.

## Grilled decisions

### D1 — Separate flake or keep local?

**Decision:** implemented as a separate flake.

**Reason:** the local module proved enough behavior to define a small stable API:
global instruction rendering, inline RTK guidance, style guidance, and opt-in
TOML config.

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

### D5 — Install or generate RTK?

**Decision:** do not install RTK by default; support generated guidance only
when the consumer provides an RTK package.

**Reason:** RTK package provenance is external, but generation can be useful for
users who already package RTK. Default remains the safer reduced wording.

### D6 — Name `programs.codex`?

**Decision:** avoid it for now; use `programs.codex-profile`.

**Reason:** Home Manager may eventually grow an official `programs.codex`.
Squatting the obvious name creates future migration pain. A profile module can
later be folded into or renamed around an official module.

## Implementation checklist

1. ✅ Created `~/Documents/erik/codex-flake`.
2. ✅ Scaffolded like `hermes-flake`: `flake.nix`, `modules/home-manager.nix`,
   `checks.nix`, `README.md`, `Justfile`, `templates/default`.
3. ✅ Added checks:
   - Home Manager module evaluates.
   - rendered `AGENTS.md` contains RTK inline and caveman text.
   - `configFile.enable = false` does not create `.codex/config.toml`.
   - opt-in `configFile.settings` renders TOML.
   - Codex package is not installed by default.
   - generated RTK mode renders from a provided RTK package.
4. ✅ Added `desktop-nixos` input through FlakeHub:
   `codex-flake.url = "https://flakehub.com/f/ErikBPF/codex-flake/*";`
5. ✅ Replaced local `modules/dev/codex.nix` text rendering with:
   `imports = [inputs.codex-flake.homeManagerModules.default];`
   plus local policy under `programs.codex-profile`.
6. ✅ Verified with:
   - `just fmt-check`
   - `just docs-check`
   - `nix flake check --print-build-logs` in `~/Documents/erik/codex-flake`
   - `just build laptop`
   - deployed file checks for inline RTK, caveman full style, and unmanaged
     `config.toml`.

Live Codex behavioral probes were done during the original validation and proved
that global `AGENTS.md` loads while `@RTK.md` include expansion did not. The
final implemented state therefore intentionally relies on inline RTK guidance.

## Rejected shortcuts

- **Only keep `desktop-nixos` local:** simplest today, but every future agent
  profile tweak remains tangled with host config.
- **Shell out to `rtk init -g --codex` in activation:** imperative, not
  reproducible, mutates files Home Manager should own, and restores unsafe
  wording.
- **Manage whole `~/.codex`:** unsafe. It contains auth, logs, session DBs,
  cache, shell snapshots, and mutable app state.
- **Force `config.toml`:** convenient for one user, hostile as reusable default.

## Closed question

Whether the first external repo should be called `codex-flake` or a broader
`agent-profile-flake`.

**Decision:** `codex-flake`. The Codex file layout and behavior probes are
specific enough that a generic agent framework would dilute the first version.
