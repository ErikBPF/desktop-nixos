# Orion repository storage

**Status:** Copy staging in progress, 2026-09-07; activation and verification pending.

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
