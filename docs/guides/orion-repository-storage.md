# Orion repository storage

**Status:** Declarative placement implemented; rollout results are tracked in the
[homelab proposal](https://github.com/ErikBPF/homelab/blob/main/docs/proposals/2026-09-07-orion-apollo-development-stability.md).
Staging on 2026-09-07 passed checksum comparisons for all 21 personal repos;
nine missing Git repositories were initialized and all 28 sister links matched.

The 21 personal repositories listed in `modules/hosts/orion/workspace-storage.nix`
live under `/projects/workspaces/erik`. Bind mounts retain their existing
`~/Documents/erik/...` paths, including `code/home-assistant-config` and `ha-agent`.
`l1/l2` still enter the homelab umbrella; its gitignored `references/repos` links
retain the operator workstation layout. Work-owned repos and upstream reference
caches retain their original paths. Apollo is unaffected.

Syncthing already carries the Documents working files. Git metadata is excluded
and remains local. Never copy credentials or synchronize live `.git` directories.
Missing Git metadata is seeded through Git transport, without overwriting working
files; existing branches, staged changes and unpublished history are preserved.
Endeavour's source commits are also imported under `refs/remotes/endeavour/...`
without changing existing Orion HEADs or indexes. Upstream reference caches are
shallow Git fetches at the recorded source commits, outside Documents sync.
This provisioning is not a two-writer Git reconciliation protocol.

## One-time staging and cutover

Use an isolated desktop-nixos checkout outside synchronized Documents. Inventory
from the homelab `repos.json`, resolve canonical source paths and inspect remote
Git state before changing anything. Require `/projects` UUID
`d4511ef9-7f62-4f0f-86d2-ee015344c289` and enough free space. The initial selected
personal trees total about 16 GiB; all Documents would exceed available space.

Create a mode-0700 root-owned staging directory at
`/var/lib/orion-workspace-staging-20260907` and a read-only Btrfs snapshot of
`/home` at its `home-before` child. Stage each selected snapshot tree into its
new `/projects/workspaces/erik` path with `sudo rsync -aHAX --numeric-ids`.
Preserve originals and the snapshot; this cutover deletes neither.

Before cutover, pause Orion's Documents folder using its authenticated local
Syncthing API. Read the API key from existing config only in memory; never log it.
Check `/proc` for processes using selected paths; stop if writers are active.
Final-copy each live source to the staged tree with rsync, retaining superseded
staged files in a private backup directory when reconciling deletions. Require
checksum dry runs to report no differences. Do not change the remote source
checkout's branch or overwrite an existing Git index.

Run `just lint`, `just fmt-check`, `just dry orion`, and
`just deploy-rs-preview orion`; inspect activation changes before
`just switch-orion`. Syncthing requires every selected mount before starting.
After activation, verify all 21 paths resolve to the projects UUID, their files
match the final copy, existing Git HEAD/index values remain unchanged, and
homelab's manifest links resolve to local repositories. Resume Documents sync;
verify a temporary nonsensitive probe transfers, then remove the probe and
verify its deletion converges. Existing unrelated protected-directory deletions
are not permission to erase ignored Git history or local artifacts.

Verify SSH, Syncthing, Steam, inference and failed units. Keep the original
system-disk trees and snapshot until a separately reviewed cleanup. For rollback,
stop writers and sync first, preserve new writes, and reconcile them before
returning to the prior mount configuration; unmounting alone would expose stale
original files.

## Retained legacy directories

Orion Documents adds `modules/common/stignore-orion-retained` to the shared
ignore rules. Its 41 exact rooted exclusions cover 923 directory deletions
blocked by ignored local files on 2026-09-07. Each root was verified as globally
deleted and locally present before exclusion. Files remain in place, including
local Git history and artifacts; these paths no longer receive or send changes.
Five exclusions are narrow subdirectories inside otherwise active work repos.
The homelab/dataplatform umbrellas and other sister repo paths remain in scope.
Apollo and Orion's other folders keep their existing filters.

Use `/path` without a trailing slash to match the directory itself and its
children. Never use `(?d)` to silence these errors: it permits removal of ignored
files. See [Syncthing's ignore semantics](https://docs.syncthing.net/users/ignoring.html).
Before adding or removing an exclusion, inspect both the live global index and
retained local files. Reintroducing a globally deleted path can resume deletion;
copy/reconcile any wanted files outside that tombstoned path first.

Deploy with the verification and `just switch-orion` sequence above. Changes to
any declared ignore file restart Syncthing after tmpfiles installs its symlink.
This is necessary because Syncthing caches rules by modification time, while Nix
store files have a fixed timestamp; a scan alone can retain the previous rules.
The existing index survives the restart. Request a Documents scan through the
authenticated local API if needed, without resetting the index.
Require an unpaused, idle folder with no pending items or errors; compare retained
file metadata before/after and verify an active repo probe in both directions
with Apollo, including deletion of the probe.
