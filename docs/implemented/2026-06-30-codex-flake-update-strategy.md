# codex-flake update strategy

**Status:** Implemented. **Date:** 2026-06-30.
**Audience:** Maintainer of `codex-flake` and `desktop-nixos`.
**Post-read action:** Implement the opt-in fast Codex package lane while keeping
the default profile module conservative.

## 1. Context

`codex-flake` currently exports a reusable Home Manager profile module. It
manages global Codex files, optional RTK guidance, optional style guidance, and
optional `config.toml`. It does not own the Codex package by default; the module
uses the consumer's `pkgs.codex` when package installation is enabled.

`desktop-nixos` consumes `codex-flake` through FlakeHub and makes its
`nixpkgs`, `home-manager`, and `flake-parts` inputs follow the desktop flake.
That is correct for profile integration, but it means a new `codex-flake`
release does not update the Codex binary. The Codex binary follows the
consumer's `nixpkgs` lock.

`claude-code-nix` is different. It owns the Claude package, polls upstream
hourly, rewrites version and fixed hashes, builds the result, opens an automated
PR, auto-merges after CI, and tags releases. That strategy works because the
flake owns the package derivation.

## 2. Goal

Give `codex-flake` an update strategy with the same user outcome as
`claude-code-nix`: a consumer can opt into a faster, validated Codex update lane
without waiting for `nixpkgs`.

Non-goals:

- Do not manage Codex auth, sessions, cache, history, or mutable runtime state.
- Do not make the fast package mandatory for all profile consumers.
- Do not block consumers who prefer `pkgs.codex` from their own `nixpkgs` pin.

## 3. Options

### Option A — Profile-only, automate lock freshness

Keep `codex-flake` as a Home Manager profile flake. Add scheduled dependency PRs
that update `flake.lock`, run checks, publish to FlakeHub, and stop there.

Pros:

- Smallest maintenance surface.
- No Rust package build burden in this repo.
- Consumers retain full control through their own `nixpkgs`.

Cons:

- Does not solve fast Codex updates for `desktop-nixos`, because the desktop
  input makes `codex-flake.nixpkgs` follow the desktop lock.
- FlakeHub releases look fresh while the installed Codex binary may still lag.

Use this if `codex-flake` is only a profile module.

### Option B — Add optional fast Codex package

Add a package output to `codex-flake` and make the profile module able to install
that package when the consumer opts in.

Expected flake surface:

```nix
{
  packages.default = self.packages.${system}.codex;
  packages.codex = ...;
  overlays.default = final: prev: {
    codex-latest = self.packages.${prev.stdenv.hostPlatform.system}.codex;
  };

  homeManagerModules.default = ...;       # profile-only default
  homeManagerModules.withPackage = ...;   # profile + self package default
}
```

Consumer posture:

```nix
imports = [ inputs.codex-flake.homeManagerModules.withPackage ];

programs.codex-profile = {
  enable = true;
  package.enable = true;
};
```

Pros:

- Matches the real `claude-code-nix` update model.
- Lets `desktop-nixos` update Codex by updating only `codex-flake`.
- Allows a clear trust split: profile-only users avoid package churn; package
  users accept the fast lane deliberately.

Cons:

- Requires owning package maintenance and CI cost.
- Codex is Rust-based and heavier to build than Claude's prebuilt native binary.
- `nixpkgs` already packages Codex; this may duplicate work.

Use this if fast Codex updates matter enough to justify owning the package.

### Option C — Track an upstream package flake

If a credible Codex package flake appears, consume it as an optional input and
wire `programs.codex-profile.package.package` to that package.

Pros:

- Keeps `codex-flake` focused on profile behavior.
- Avoids owning upstream package breakage.

Cons:

- No known reusable package flake exists today.
- Adds supply-chain trust in another maintainer without removing the need for
  validation.

Use this only if a reliable upstream flake exists and has a better update
posture than `nixpkgs`.

## 4. Recommendation

Implement Option B, but keep it opt-in.

`codex-flake` should remain profile-first. The default module should not install
the self-owned package unless explicitly requested. A named module or package
option can provide the fast lane for `desktop-nixos` and any other consumer that
wants it.

This gives two stable modes:

- **Conservative:** import the default module, install `pkgs.codex`.
- **Fresh:** import the package-aware module, install `codex-flake`'s package.

Resolved decisions from review:

- `codex-flake` will become package-owning, but only through an opt-in fast
  lane.
- The default Home Manager module remains profile-first and uses `pkgs.codex`.
- The fast lane is exposed through `homeManagerModules.withPackage`, not a
  general `source = "nixpkgs" | "self"` option.
- GitHub Rust release tags are the package source of truth; npm is advisory
  only.
- Automated update PRs may auto-merge after required checks pass.
- Package bump tags use `codex-vX.Y.Z`; plain `vX.Y.Z` remains available for
  flake/profile API releases.

## 5. Proposed implementation

### Phase 1 — Package output

Add a package expression based on the current `nixpkgs` Codex package:

- fetch from `openai/codex` release tags named `rust-vX.Y.Z`;
- build only the `codex-cli` package;
- keep shell completions and wrapper behavior;
- keep upstream-compatible metadata;
- expose `packages.codex`, `packages.default`, `apps.codex`, and `apps.default`;
- expose `overlays.default`.

Prefer using `nix-update-script` over custom text rewriting where possible. The
current nixpkgs package already encodes the right update source:

```nix
nix-update-script {
  extraArgs = [
    "--use-github-releases"
    "--version-regex"
    "^rust-v(\\d+\\.\\d+\\.\\d+)$"
  ];
}
```

### Phase 2 — Update script

Add `scripts/update-codex.sh` with the same operational contract as the Hermes
updater:

- `--check` exits 1 when a newer upstream release is available;
- `--version X.Y.Z` pins a specific release;
- default updates to latest;
- update package version, source hash, cargo hash, and lock file;
- build `.#codex`;
- smoke test `codex --version`;
- show a diff summary.

Fetch latest from GitHub releases first. Use npm `@openai/codex` only as a
secondary comparison signal, because the nixpkgs package tracks Rust release
tags.

### Phase 3 — CI automation

Add a scheduled workflow:

- schedule: daily to start;
- manual dispatch;
- run update script with `--check`;
- apply update when needed;
- create PR with `dependencies` and `automated` labels;
- run Linux build and smoke test;
- enable auto-merge only after required checks pass.

Do not start hourly. Codex builds are heavier than Claude's native binary
package. Increase cadence only after cache and CI timings are known.

TODO: review cache hit rate and CI runtime before considering a 6-hour or hourly
cadence.

### Phase 4 — Release tags

Add tag automation after successful main builds:

- immutable `codex-vX.Y.Z` tag for package bumps;
- optional moving `latest-codex` tag;
- keep FlakeHub rolling releases as the normal consumption path.

Avoid ambiguous plain `vX.Y.Z` if the flake itself also needs semantic releases
for profile API changes.

### Phase 5 — Home Manager package policy

Keep `programs.codex-profile.package.package = pkgs.codex` in the default
module. Add:

- `homeManagerModules.withPackage`, which defaults the package to
  `self.packages.${system}.codex`.

The named module makes the package trust boundary visible at import time and is
less invasive than adding a package-source option to the profile module.

## 6. Verification

Required checks:

- module renders `AGENTS.md`;
- RTK generated and reduced modes still work;
- `config.toml` remains off by default;
- package remains off by default;
- package-on installs a selected fake package in a cheap module test;
- `.#codex` builds on `x86_64-linux`;
- `codex --version` reports the packaged version;
- update script `--check` has deterministic exit codes.

Nice-to-have checks:

- `aarch64-linux` build on GitHub ARM runner;
- `aarch64-darwin` build if a runner is available;
- closure-size guard to catch accidental full workspace/runtime bloat.

Publishing initially requires the fast eval/module/lint gate. The
`x86_64-linux` package build and smoke test are validated locally and remain
advisory in GitHub Actions until runner availability, cache hit rate, and build
time are proven acceptable. ARM builds stay advisory for the same reason.

## 7. Security and trust

Adding a package changes the trust model. Profile-only `codex-flake` mostly
ships text files. Package-owning `codex-flake` ships an executable coding agent.

Document these modes clearly:

- profile-only consumers trust the module text and Home Manager behavior;
- package consumers trust this repo's update workflow, GitHub Actions, upstream
  OpenAI release artifacts, and any binary cache used;
- building locally avoids binary-cache trust but costs time.

Pin GitHub Actions by SHA before enabling auto-merge on package bumps.

`desktop-nixos` imports `homeManagerModules.withPackage` from the FlakeHub
release containing that module and `packages.x86_64-linux.codex`.

## 9. Implementation slices

1. **Package output:** add package expression, packages/apps/overlay, and one
   Linux build check.
2. **Module opt-in:** add package-aware Home Manager module and cheap tests for
   package selection.
3. **Updater:** add script with `--check`, `--version`, build, smoke, and diff
   summary.
4. **CI PR flow:** add scheduled update workflow with auto-merge guarded by
   required checks.
5. **Release hygiene:** add package bump tags or explicitly document why tags
   are omitted.
6. **Consumer adoption:** switch `desktop-nixos` to the package-aware module
   after the first verified FlakeHub release publishes.
