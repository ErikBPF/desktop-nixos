# Kepler compute-pool folders

**Status:** Accepted behavior; implementation in progress.

Human seed (verbatim):

> we should syncthing both to folders on compute volume. For kepler it is local. Les map folders to this pool

Accepted clarifications:

> Use only explicit compute-pool paths

> Yes: local copies on each host

Documents and Downloads remain local on Endeavour. Kepler receives independent,
bidirectional copies at `/fast/compute/erik/Documents/` and
`/fast/compute/erik/Downloads/`, on its existing `fast-pool/data` dataset.
No home aliases, NFS-backed Syncthing copies, or migration of existing home data.
Retain the fleet ignore policy, existing peers, `.kube` scope and tofu-state mirror.
Create the pool folders and their ignore links only after `/fast` is mounted;
stop Syncthing if the mount disappears.
