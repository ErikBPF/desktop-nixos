# GitHub fork mirror sync

**Status:** Manual command prepared; unattended sync disabled pending scoped
nonhuman credentials.

Fast-forward sync of personal GitHub fork mirrors to their upstreams. Implemented by the `github-fork-sync` home module
(`modules/desktop/github-fork-sync.nix`), active on hosts importing
`profile-desktop`.

## What it does

- For each entry in the module's `forks` list: fetch the upstream branch into
  its tracking ref, then push it to the fork — **fast-forward only**.
- Diverged forks are skipped with a warning, never force-pushed. Missing local checkouts are skipped without error; diverged or unreachable
  repositories produce a non-zero exit status.
- Runs only when explicitly invoked. No timer or user service is declared.

## Adding a fork

Append a line to the module's `forks` list:

```
<path>:<upstream-remote>:<upstream-branch>:<fork-remote>
```

Remote names are per-repo git remotes (e.g. `upstream:dev:origin` for LMCache).
Repos whose fork branch carries private work (e.g. `llama-cpp-private`) must
**not** be added — rebase those manually. Currently synced: litellm, LMCache,
delta-rs, sail, FreeToken, airflow, datafusion-comet.

## Auth

Git uses each remote's configured SSH or HTTPS authentication. Review the
remote targets before invoking this command; it pushes to every listed fork.
Interactive credentials must not be reused by unattended timers. Restore
scheduling only after provisioning a separate nonhuman credential per target
trust boundary, with explicit fork-only write access. No credential is created
or copied by this module.

## Verification

The script is on `$PATH` via the module's `home.packages`. Run it manually:

```
github-fork-sync
```

A successful run exits 0. Missing repositories are reported and skipped;
diverged or unreachable remotes cause a nonzero exit. Run only when those
pushes are intended.
