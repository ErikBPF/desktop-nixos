# Codex tooling reconciliation

**Status:** implemented in PR #329; no live activation in this slice.

Home Manager installs the pinned RTK binary, missing vendored skills and Graphify
reference files. Its existing Codex activation installs Ponytail from a catalog
whose plugin source is pinned to the flake input revision. The UI updater changes
only quota/context/model display fields, disables automatic recap and enables the
plan tool; TOML comments and unrelated mutable settings survive an atomic private
file replacement. Existing profile overlays are preserved.

Current main's gateway headers, model inheritance, shared feedback policy and
PL/IP/RV instructions remain authoritative. The older working tree's Headroom
endpoint redirection and scoped overlay are excluded: the proposed service still
references an imperatively installed binary. Headroom remains deferred, not an
unfinished mandatory part of this rollout. The [earlier evaluation](../implemented/2026-07-02-tokensave-dataplatform-eval.md)
deferred overlapping compression middleware because stacking lossy layers with
RTK can undermine correctness. Reopen only for an accepted need with a scoped
behavior contract; then require a reproducible package or an explicit external
runtime contract before redirecting the default endpoint. Packaging alone does
not settle adoption. Preserve the saved draft and existing profile overlays.

Validation: 28 actual pytest checks using declared Nix Python with `tomlkit` and
`pytest`; lint, format, documentation and dry builds for Endeavour, Pathfinder,
Orion and Apollo pass.

Pinned Codex 0.154.0's read-only marketplace listing exposes `marketplaces` with
`name` and `root`. Its [tagged marketplace parser](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/core-plugins/src/marketplace.rs#L1019)
accepts URL plugin sources with the `ref` selector and maps that selector to the
Git source. CLI and schema checks made no changes to the user's configuration.

The same tagged marketplace implementation returns success for an already-added
local root; plugin installation atomically replaces an existing same-version
cache. Repeated activation is supported. The scoped RTK derivation was built and
its executable reported `rtk 0.48.0`. No profile overlay was removed.
