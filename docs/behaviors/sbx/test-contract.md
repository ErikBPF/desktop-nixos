# Docker Sandboxes test contract

**Status:** Focused gates verified; fleet dry-build environment-blocked.
**Date:** 2026-08-28.

| Gate | Expected evidence |
|---|---|
| Source contract | Focused pytest requires version 0.39.0, the official release repository, fixed hash, package-scoped unfree predicate, x86-64 restriction, auto-patching, and `e2fsprogs`. |
| Profile contract | Focused pytest requires Codex, clone mode, 4 CPUs, and 8 GiB memory. |
| Build contract | `nix build .#sbx --no-link` succeeds without `NIXPKGS_ALLOW_UNFREE` or `--impure`. |
| Runtime smoke | `nix run .#sbx -- version` reports version 0.39.0 without creating a sandbox. |
| Repository gates | CI reruns the focused pytest, build, and runtime smoke; `just docs-check`, `just lint`, and `just fmt-check` pass. |

A live sandbox is intentionally excluded: it requires user OAuth/credentials,
KVM access, network policy selection, and persistent runtime state. Those are
host/operator acceptance concerns, not package-build evidence.
