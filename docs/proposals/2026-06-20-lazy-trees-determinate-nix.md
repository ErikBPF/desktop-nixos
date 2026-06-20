# Lazy-trees for the host repo (via Determinate Nix)

**Date:** 2026-06-20
**Status:** Plan (skeleton — judgment marked `TODO(erik)`)
**Owner:** erik
**Scope:** the `desktop-nixos` flake's eval performance (CI + local), not the
fleet's runtime.

> Lazy-trees makes Nix copy only the flake sources an eval actually needs into
> the store, instead of the **whole** working tree every time. For a big
> dendritic repo (`modules/` + `_bmad/` + `docs/` + `references/`), that's a real
> eval-time and store-churn win. It is currently **exclusive to Determinate Nix**
> (the upstream PR is still open), so adopting lazy-trees = adopting Determinate
> Nix where we want it.

---

## 1. Goal

Cut flake eval time and store writes by enabling **lazy-trees**. Two surfaces:
- **CI** — the `eval` matrix (5 hosts) + the `k3s-smoke` build each copy the repo
  tree to the store. Lazy-trees shrinks that. CI **already runs Determinate Nix**
  (`DeterminateSystems/nix-installer-action`), so this is mostly a flag flip.
- **Local/hosts** — interactive `nix eval` / `just dry` / `switch` on the laptop
  and the build hosts (orion). Needs Determinate Nix on those machines.

Non-goal: changing anything about the fleet's *runtime* (services, k3s, etc.).
This is purely the Nix evaluator/builder.

## 2. Why this repo benefits (the size problem)

Without lazy-trees, every `nix eval`/`flake` op copies the entire flake working
tree into `/nix/store` (then evaluates). This repo carries a lot that no eval
needs: `_bmad/`, `docs/`, `references/`, the `modules/` tree, etc. Reported
lazy-trees wins on comparable repos: eval ~11s→3.5s, store usage ~300 MB→13 MB
(>20× less). We run that copy **6× per CI push** (lint + 5-host eval matrix) and
constantly during local iteration. `TODO(erik)`: baseline our actual numbers
(`time nix eval .#nixosConfigurations.kepler...drvPath` + store delta) before/after
so the win is measured, not assumed.

## 3. Current state (2026-06)

- **lazy-trees is Determinate-Nix-only.** Upstream Nix PR open; not in nixpkgs'
  `nix` yet. So the feature ships via Determinate Nix, which runs the full Nix +
  nixpkgs-lib test suites with lazy-trees on (two bugs found + fixed upstream).
- **CI already uses Determinate Nix** (`nix-installer-action@v16`) → lazy-trees is
  one setting away there.
- **Hosts run nixpkgs' `nix`** (standard NixOS). Getting lazy-trees on a host =
  installing Determinate Nix on it (Determinate ships a NixOS module / flake
  input). `TODO(erik)`: confirm the Determinate NixOS module path + that the
  lazy-trees-bearing build is in the **free** tier (no login/enterprise gate).

## 4. Plan (staged, lowest-risk first)

### 4a. CI — enable lazy-trees (cheap, reversible, measurable)
Determinate Nix is already installed by the action; turn lazy-trees on for the
`eval`/`k3s-smoke` jobs via the installer's Nix config (e.g.
`extra-conf: lazy-trees = true`, or the action's determinate option). Measure the
`eval` matrix wall-clock before/after. If it regresses or misbehaves, drop the
flag — zero fleet impact. `TODO(erik)`: exact knob (installer input vs
`/etc/nix/nix.conf` extra-conf).

### 4b. Build host (orion) — opt in next
orion does the heavy fleet builds (and the aarch64 archinaut work). Lazy-trees
there speeds remote-build eval + trims its store churn. Adopt Determinate Nix on
orion via its NixOS module, behind a flag, and verify a full `just dry`/build is
byte-identical to before. orion is the right canary — it's a build host, not a
daily driver.

### 4c. Laptop — interactive dev
Biggest day-to-day felt win (every `nix eval`/`just dry` during iteration).
Adopt after orion proves clean.

### 4d. Rest of the fleet — only if 4b/4c are clearly net-positive
The other hosts (kepler/discovery/pathfinder) rarely eval locally; lazy-trees
helps them little. `TODO(erik)`: probably **not worth** swapping their Nix —
keep them on nixpkgs `nix` unless there's a reason. Lazy-trees is an *eval-side*
win; these hosts mostly *receive* closures.

## 5. Tradeoffs / risks (judgment — `TODO(erik)`)

- **It's a different Nix distribution.** Determinate Nix ≠ nixpkgs `nix`: their
  hardening, auto-GC defaults, `determinate-nixd`, possible telemetry/login.
  Confirm the free tier covers lazy-trees with no account requirement, and that
  auto-GC won't fight our pinned generations (kepler's `configurationLimit`,
  cache retention).
- **Dendritic `import-tree` interaction.** Our hard rule — *new files must be
  `git add`ed before eval sees them* — is a git-tracked-files behavior;
  lazy-trees still resolves the git tree, so the rule should hold, but **verify**
  (a lazy-trees eval must see the same module set; a missing module = the
  misleading "attribute missing"). Run the full 5-host eval and diff drvPaths
  against nixpkgs-`nix` to prove behavior-equivalence.
- **Version coupling.** Determinate Nix tracks its own release cadence; pinning it
  as a flake input adds another bump to manage (like hermes-flake). `TODO(erik)`:
  acceptable vs the eval win?
- **Reversibility.** CI (4a) is trivially reversible. Host adoption (4b+) is a
  Nix-implementation swap — keep it flag-gated + canary on orion first.

## 6. Verify (per step)

- 4a: CI `eval` matrix green + faster wall-clock; `k3s-smoke` still passes.
- 4b/4c: `nix eval .#nixosConfigurations.<host>...drvPath` identical to the
  pre-switch hash (behavior-preserving); `just dry <host>` clean; measured eval
  speedup + store-delta logged here.

## 7. Open questions — `TODO(erik)`

- Exact lazy-trees enable knob in the installer action / host module.
- Determinate Nix free-tier scope on NixOS (login? telemetry? GC defaults?).
- Baseline + post numbers (eval time, store delta) — decide go/no-go on data.
- Fleet scope: orion + laptop only, or wider?
