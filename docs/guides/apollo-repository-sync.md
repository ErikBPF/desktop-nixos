# Apollo repository sync

**Status:** Declarative Documents sync prepared; execution evidence belongs in the homelab proposal.

Apollo keeps repositories under `/home/erik/Documents` on its system disks.
Use its existing Syncthing identity and only Orion as a new peer. Share the
existing Documents folder ID with an Apollo-specific selected-repository filter.
Do not share Downloads, kube or state mirrors. Git metadata, credentials,
worktrees and local agent state are excluded; Git owns committed history.
Exclude `graphify-out` as generated cache: it can contain entire copied working
trees. Environment-file exclusions cover `.env`, `.env.*` and `.env-*`; tracked
`.envrc` files remain eligible for sync.

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
Stage Apollo's generation with `just deploy-rs-boot apollo`; its full live switch
would restart the five VMs and apply unrelated pending changes. Keep the running
generation and VM processes intact. Apply the generated ignore link first. Read the device and folder JSON fragments
referenced by Nix's generated Syncthing updater; create the Orion device and
Documents folder through the authenticated local API, changing only the initial
folder type to `receiveonly`. Verify that setting before deploying Orion. Do not
run the native updater until catch-up is accepted: it declares `sendreceive`. Credentials stay in
process memory, never output or plaintext files. Apollo retains staggered
version history. Deploy Orion through `just switch-orion`; never override or
revert local changes in the Syncthing UI/API to force convergence.

Wait for selected file downloads to complete. Verify all selected Git repos,
source commit availability, original HEADs/indexes and reference links. Inspect
receive-only changes/conflicts and preserve any unique files. Only after clean
acceptance run the targeted updater below to apply the declared `sendreceive` mode. Test
nonsensitive creation, return edit and deletion; test that credential-shaped
and worktree canaries remain excluded, then remove the canaries. Do not infer a
complete Git/WIP handoff or independent restore proof from file transport.

Run lint, format, focused tests, Orion/Apollo dry builds and activation previews
before the boot-stage/targeted Apollo update and `just switch-orion`.
Verify SSH, Syncthing, persistent sessions, Apollo's five VM/k3s nodes, Nix-cache
access, disk headroom and failed units. Keep the snapshot for rollback; pause
writers/sync and reconcile new work before any recovery. Never roll back by
silently overwriting the active Documents tree.

## Targeted Apollo activation

After the merged source is built/copied by `just deploy-rs-boot apollo`, derive
the live update directly from its Nix outputs. Do not hand-copy API settings.
Apply the ignore link before first join; run the runtime updater only after
receive-only catch-up and preservation checks have passed.
Require no preexisting runtime override at the path below; preserve VM PIDs and
activation timestamps before/after. Nix's native updater uses its normal private
`/run/syncthing-init` directory for runtime API authentication; never print it.

```sh
APOLLO_SYNC_INIT=$(nix eval --raw .#nixosConfigurations.apollo.config.systemd.services.syncthing-init.serviceConfig.ExecStart)
APOLLO_SYNC_IGNORE=$(nix eval --json .#nixosConfigurations.apollo.config.systemd.tmpfiles.rules | jq -r '.[] | select(startswith("L+ /home/erik/Documents/.stignore "))')
test -n "$APOLLO_SYNC_INIT"
test -n "$APOLLO_SYNC_IGNORE"
printf '%s\n' "$APOLLO_SYNC_IGNORE" | ssh -p 2222 erik@apollo 'sudo systemd-tmpfiles --create -'
ssh -p 2222 erik@apollo 'test ! -e /run/systemd/system/syncthing-init.service.d/override.conf'
printf '[Service]\nExecStart=\nExecStart=%s\n' "$APOLLO_SYNC_INIT" | ssh -p 2222 erik@apollo 'sudo systemctl edit --runtime --stdin syncthing-init.service'
ssh -p 2222 erik@apollo 'sudo systemctl restart syncthing-init.service'
```

This runtime override points to the same generated updater as the staged
next-boot generation. It disappears at reboot, when that generation supplies
the permanent unit. No reboot or full Apollo live switch is part of this task.

## LAN recovery after hardware changes

The physical uplink changed to `enp5s0` after the GPU exchange. The MAC-based
link rule now assigns `lan0`, shared by DHCP and VM NAT. An already-running
interface does not acquire that new name just by switching generations; coordinate
the controlled reboot with the hardware recovery before expecting LAN access. If Apollo is reachable only through Tailnet, use the existing
recipes with a hostname override: `just deploy-rs-preview apollo apollo`, then
`just deploy-rs apollo apollo`. Inspect the activation preview and verify the
reserved LAN address, VM egress and `just diagnose-apollo-worklab` afterward.

Keep the Apollo peer paused on Orion throughout an interrupted first join. A
reboot into the staged generation applies declared send/receive mode, so check
Apollo's folder state before releasing the hold. Reconcile its local index and
working files in receive-only mode before enabling two-way transport.
