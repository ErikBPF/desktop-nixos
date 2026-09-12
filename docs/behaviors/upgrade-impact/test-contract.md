# Evaluated upgrade impact

**Status:** Authorized U2 continuation; implementation pending.

Source: homelab's accepted fleet-upgrade proposal and
`docs/behaviors/fleet-upgrade/upgrade.feature`. The September 12 continuation
implements the evaluated-identity seam before the separately gated ESP check.
The historical human-authored upgrade seed is not modified.

## Contract

```yaml
command: just upgrade-impact before after
inputs: two explicitly selected flake snapshots without an attribute fragment
evaluation:
  source: fleet.hosts excluding role=appliance, with a required nixosConfigurations entry
  identity: config.system.build.toplevel.drvPath
  offline: true
  write_lock_file: false
  allow_import_from_derivation: false
output:
  format: JSON on stdout, only after both evaluations and validation succeed
  affected: map of host to before/after derivation paths
  unchanged: map of host to unchanged derivation path
failure:
  exit: nonzero
  stdout: empty
  causes: [evaluation_failure, invalid_identity, empty_host_set, topology_change]
  diagnostics: fixed phase-specific message; no raw Nix stderr or flake URLs
side_effects: no update, build, SSH, activation, or notification
tests: python3 -m unittest discover -s tests/update-safe -v
```

Use the evaluated fleet registry and require a NixOS configuration for each
managed host. Exclude appliance roles and auxiliary configurations absent from
the registry; do not infer impact from filenames or lock input names.
A host addition/removal requires separate review and
cannot silently disappear from the report. Evaluation can populate local
derivation metadata; offline mode and disabled import-from-derivation prevent
network fetching and evaluation-triggered builds. Uncached or IFD-dependent
snapshots fail closed.

This reports candidate impact, not attribution exclusively to input changes.
Source or revision metadata changes may conservatively affect many hosts.
It does not establish that either snapshot is a clean published baseline,
that affected outputs are realized, or that any host is safe to activate.
U1's lock hashes cannot reconstruct the before snapshot; the operator must
retain and select both snapshots. Connecting this report to scoped builds is
separate work.

## Existing build coverage correction

`build-all` must enumerate the same evaluated managed configuration names rather
than its incomplete static list. Send non-Endeavour targets through the
existing remote-builder flags; build Endeavour separately with no builders.
Enumeration failure, empty/invalid names, or a failed build stops the recipe.
Do not change deployment commands, builder selection, or the `dry-all` alias.
One shared Nix selection expression keeps these two callers aligned. The
September 12 source check found `drtest`, `archinaut-base`, and
`orion-esp-installer` alongside standing configurations, so selecting every
`nixosConfigurations` key would silently expand the managed fleet.

## Verification

Real input-free local Nix fixtures establish leaf, shared, and unchanged
derivation comparisons without realizing outputs. Cover failed evaluation,
invalid identities, added/removed hosts, literal argument handling, and
sanitized failure output. Exercise the real Just recipes with subprocess
boundaries where real builds would otherwise occur. Assert Apollo and a
future configuration are included and Endeavour keeps its local-only lane.

Rollback: revert the impact helper/recipe and restore the previous build
enumeration. No host state or fleet lock is changed by this implementation.
