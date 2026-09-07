# Apollo repository sync

**Status:** Declarative Documents sync prepared; execution evidence belongs in the homelab proposal.

Apollo keeps repositories under `/home/erik/Documents` on its system disks.
Use its existing Syncthing identity and only Orion as a new peer. Share the
existing Documents folder ID with an Apollo-specific selected-repository filter.
Do not share Downloads, kube or state mirrors. Git metadata, credentials,
worktrees and local agent state are excluded; Git owns committed history.

## Guarded first join

Inventory from homelab's local `repos.json`. Before seeding or connecting,
compare Apollo's dirty files to the source; stop on unique conflicting work.
Keep existing HEADs/indexes. Create a root-owned mode-0700 directory
`/var/lib/apollo-repo-staging-20260907` and a read-only Btrfs snapshot of `/home`
at its `home-before` child. Do not delete original data or reset existing repos.
Check for active writers; idle persistent shells can retain their paths.

Seed missing repositories with Git bundles over encrypted SSH, verifying the
recorded source commit. Populate only new empty directories. Import source
commits for existing checkouts under `refs/remotes/endeavour/...` without
checking them out. Place upstream reference clones under
`~/Documents/erik/upstream/` and expose host-local aliases at the preexisting
`~/.graphify/repos/...` reference paths; those clones are outside the selected
Syncthing working-file set. Preserve matching umbrella reference links.

Apply the reviewed IaC ACL on wired Orion: only the two Apollo/Orion TCP 22000
grants may change. Validate policy tests and require a zero-drift follow-up.
Deploy Apollo first, while Orion still does not know its Syncthing identity.
Before deploying Orion, use the authenticated local API to set Apollo's
Documents folder to `receiveonly`, and verify the setting. Credentials stay in
process memory, never output or plaintext files. Apollo retains staggered
version history. Deploy Orion through `just switch-orion`; never override or
revert local changes in the Syncthing UI/API to force convergence.

Wait for selected file downloads to complete. Verify all selected Git repos,
source commit availability, original HEADs/indexes and reference links. Inspect
receive-only changes/conflicts and preserve any unique files. Only after clean
acceptance set Apollo's folder back to the declared `sendreceive` mode. Test
nonsensitive creation, return edit and deletion; test that credential-shaped
and worktree canaries remain excluded, then remove the canaries. Do not infer a
complete Git/WIP handoff or independent restore proof from file transport.

Run lint, format, focused tests, Orion/Apollo dry builds and activation previews
before the corresponding `just switch-apollo` and `just switch-orion` recipes.
Verify SSH, Syncthing, persistent sessions, Apollo's five VM/k3s nodes, Nix-cache
access, disk headroom and failed units. Keep the snapshot for rollback; pause
writers/sync and reconcile new work before any recovery. Never roll back by
silently overwriting the active Documents tree.
