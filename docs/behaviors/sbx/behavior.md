# Docker Sandboxes repository integration

**Status:** Implemented; `/pl`, `/ip`, and `/rv` complete. **Date:** 2026-08-28.

## Seed

> run a /pl /ip and /rv loop on sbx and finish implementation

## Destination

From this repository on `x86_64-linux`, `nix build .#sbx` produces the pinned
Docker Sandboxes CLI without ambient unfree-package flags. The repository
profile runs Codex from an isolated clone with bounded CPU and memory.

## Grounded baseline

- The existing package pins Docker Sandboxes 0.39.0 and the correct artifact
  hash, but its URL names the nonexistent `docker/sbx` release repository.
- The package is proprietary, so the default per-system nixpkgs instance
  rejects `nix build .#sbx` before the derivation builds.
- Docker publishes the pinned tarball from `docker/sbx-releases`. Its bundled
  installer confirms the package layout and the `e2fsprogs` runtime dependency.
- Upstream tests Linux only on Ubuntu 24.04 or later. A real sandbox additionally
  requires x86-64 KVM access, Docker sign-in, and agent credentials.
- `.sbxenv.yaml` already selects Codex, clone mode, 4 CPUs, and 8 GiB memory.

## Decision map

```text
correct published artifact + package-scoped unfree allowance
  -> reproducible flake package
  -> sbx CLI starts from the Nix result

clone workspace + bounded resources
  -> repository-local sandbox contract
```

## Decisions

- Keep 0.39.0: it is the first version supporting environment files and the
  existing hash matches Docker's release asset.
- Allow only `docker-sbx` in a package-local nixpkgs import. Do not broaden the
  flake's unfree policy.
- Preserve Docker's tarball layout and wrap `sbx` with `mkfs.ext4` on `PATH`.
- Bind the behavior contract to one focused source test plus a real Nix build
  and `sbx version` smoke check.

## Out of scope

- Installing SBX into a host profile or deploying a host generation.
- Automating Docker OAuth, agent credentials, or a stateful sandbox run.
- Enabling KVM, AppArmor, or the privileged GPU shim.
- Claiming upstream support for NixOS.

## Review

The party pass aligned product, Nix, security, and operations perspectives on
the package-only boundary. The grill rejected a global unfree exception and a
live sandbox acceptance test because both expand scope and side effects without
improving the package contract.

## Implementation plan

One vertical slice owns the package contract; splitting URL and unfree-policy
changes would leave neither slice independently buildable.

1. **RED:** Extend `tests/sbx/test_profile.py` to require the official
   `docker/sbx-releases` URL and a package-scoped `allowUnfreePredicate` for
   `docker-sbx`. Observe the focused test fail against the current module.
2. **GREEN:** Import nixpkgs locally for this package, enable only
   `docker-sbx`, and correct the release repository. Keep the version, hash,
   installed files, wrapper, and profile unchanged.
3. **Verify:** Run the focused pytest contract, `nix build .#sbx --no-link`
   without ambient flags, and the built `sbx version`. Then run the
   repository-required lint, format, documentation, and dry-build gates.
4. **Rollback:** Revert the module and contract together. No host generation or
   persistent sandbox state is changed by this slice.

The plan grill found no missing dependency, ordering, migration, or rollout
slice. Risk review retained the proprietary license metadata and rejected both
a global unfree switch and runtime credential/KVM automation.

## Verification

The focused pytest contract, package build, `sbx version`, documentation,
lint, and format gates pass. The full fleet dry-build reached unrelated cached
host closures, then stopped on a pre-existing corrupt/missing Nix store path
(`publicsuffix-list-0-unstable-2026-03-02: Structure needs cleaning`). No host
configuration consumes SBX, so no deployment gate applies.

Behavior contract: [`sbx.feature`](sbx.feature).
