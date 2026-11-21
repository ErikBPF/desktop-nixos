# Endeavour backup: exclude the transient GVfs mount

**Status:** reviewed source repair; no live backup run or recovery claim.
**Date:** 2026-11-21.

The existing home backup exited 3 before the integrity pilot. Read-only journal
classification found one permission-denied metadata operation at the transient
`/home/erik/.gvfs` mount root; mount metadata identifies `fuse.gvfsd-fuse`.
The user-session mount is not ordinary home data and is not traversable by the
root backup. No private file names, content or credentials were recorded.

The host-owned Restic configuration now excludes exactly that mount root.
`/home/erik` remains the included source. No parent/application-state exclusion,
`--one-file-system` policy, timer change, credential change, failure-code override
or reset-failed operation was introduced. A successful normal backup is still
required before calling the baseline healthy.

The targeted actual-configuration fixture first failed because the exclusion
list was empty. After the repair, this command returned
`ENDEAVOUR_BACKUP_GVFS_OK`:

```bash
nix eval --offline --impure --raw --file tests/endeavour-home-backup.nix
```

It asserts the exact include/exclude boundary, absence of a broad filesystem
exclusion, and that exit 3 remains failure. `just lint`, `just fmt-check` and
`just structure-check` passed. One initial format-check failure in the new fixture
was corrected using the repository formatter; acceptance was unchanged.

The standard `just dry endeavour` reached an existing Orion source-cache
transport failure (connection reset/refused) and was stopped, not counted as
passed. The documented toplevel dry-run alternative then passed with a command-local
public-cache fallback:

```bash
nix build .#nixosConfigurations.endeavour.config.system.build.toplevel --dry-run --option substituters https://cache.nixos.org --option builders '' --option connect-timeout 10
```

This evaluated the complete host closure without building or activating it.
No global cache configuration or flake inputs were changed.

Root independently reviewed the two-file implementation and fixture and found
no material issue. Worktree: `worktrees/endeavour-backup-gvfs`, branch
`fix/endeavour-backup-gvfs`, base `44c67a8d1ddfc6149cd49216869f9b77c9cf5d2f`.
Publish/activation and a normal successful backup remain coordinator work.
Rollback removes only this exclusion through the owner configuration; preserve
prior failure evidence and do not mask an incomplete snapshot as success.
