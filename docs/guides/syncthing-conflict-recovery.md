# Syncthing conflict recovery

**Status:** Source-owned recovery procedure; host acceptance is recorded in homelab.

Idle Syncthing folders can still contain conflict copies. Inventory every configured
folder, including excluded Git metadata, before resolving them. Compare working-file
copies with current files and reachable Git history; keep current files only when
the older content is accounted for. Unique unresolved work stays preserved for review.
Never copy conflict Git indexes, refs, or object files over their canonical names.

`/erik/agent-evals/.local` is excluded from fleet user folders: container-owned job
outputs and session artifacts are local runtime data, not repository working files.
This does not exclude the agent-evals repository itself. Conflict names remain visible;
there is no blanket conflict ignore rule hiding future incidents.

## Capture and archive

Use an isolated checkout outside Documents. Record the API folder paths and paused
states on Apollo, Orion and Endeavour. Read API credentials only in memory. Pause all
configured folders on these three hosts through the local authenticated API before
cleanup; stop if another process is writing the conflict copies. Record current Git
HEADs, canonical index hashes and non-conflict refs for affected checkouts, plus copies
of any current working files that differ across hosts. Keep that evidence outside sync.

The helper previews by default. `--apply` creates a new mode-0700 archive, copies and
hash-verifies every selected regular conflict file, writes a metadata/hash manifest,
then rechecks sources before removing the copies from their original paths. It never
replaces normal working files. Symlink/directory conflicts, existing destinations,
archive paths inside a sync root, unreadable files and concurrent source changes fail.
A partial archive is retained on failure; use a new destination for any reviewed retry.

Run with Python 3.11+ and sudo so excluded container directories can be inventoried.
For example, for local Endeavour, with a new explicit archive destination:

```sh
sudo python3 scripts/archive-syncthing-conflicts.py --archive "$ARCHIVE" \
  /home/erik/Documents /home/erik/Downloads /home/erik/.kube
sudo python3 scripts/archive-syncthing-conflicts.py --archive "$ARCHIVE" \
  /home/erik/Documents /home/erik/Downloads /home/erik/.kube --apply
```

For a remote host, set `HOST`, `REMOTE_PYTHON` to its verified existing Nix-store
Python interpreter, and `ARCHIVE` to a new path under
`/var/lib/syncthing-conflict-recovery/`. Stream the reviewed source without editing
remote code. Apollo has only Documents; Orion also includes Downloads, `.kube` and
`/home/erik/tofu-state-backup` (append those three roots to its invocation):

```sh
ssh -p 2222 "erik@$HOST" "sudo '$REMOTE_PYTHON' - --archive '$ARCHIVE' /home/erik/Documents" \
  < scripts/archive-syncthing-conflicts.py
ssh -p 2222 "erik@$HOST" "sudo '$REMOTE_PYTHON' - --archive '$ARCHIVE' /home/erik/Documents --apply" \
  < scripts/archive-syncthing-conflicts.py
```

Pause all peers before archiving any one of them: a propagated conflict-file deletion
must not remove the other host's only copy before it has been captured. Never overwrite
an archive. Keep the full manifest and copies until independent recovery is accepted.
Restore only explicitly selected files after pausing sync and checking the destination;
blind restoration of old `.git` metadata can destroy newer history.

## Deploy scope and verify

Run the archive tests, ignore activation tests, lint/format/docs checks and affected
host dry builds. Review activation previews. Merge source before deployment.
Orion uses `just switch-orion`; Endeavour uses `just switch endeavour`. For Apollo,
follow [targeted activation](apollo-repository-sync.md#targeted-apollo-activation):
stage with `just deploy-rs-boot apollo`, install its generated Documents ignore link,
and restart only Syncthing to load the filter. Preserve the existing updater override;
no first-join reset, full live switch, VM restart or reboot belongs to this cleanup.
Recheck pauses after any updater execution and keep folders paused until all three
archives and current-file backups are verified.

Resume each folder to its captured paused state and request native scans; never use
Override/Revert or reset the index. Verify loaded exclusions, no folder errors or needs,
no conflict names under synced roots, unchanged Git HEAD/index/non-conflict refs, and
matching current working files after convergence. Check both umbrella directions with
disposable probes, then remove probes and verify deletion. Retain any newly produced
conflict copy for another content review. If one-way edits remain unindexed, inspect
watcher/scan settings rather than declaring idle status sufficient.
