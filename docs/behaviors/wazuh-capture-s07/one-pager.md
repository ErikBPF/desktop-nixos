# S07 — disabled Kepler manager capture

## Outcome and purpose

This source prepares unattended capture of the two existing Wazuh manager PVCs,
with independent recovery and a pinned encrypted-backup handoff. It enables no
host service and creates no credential. The user's exact acceptance, “do as
recomendation”, covers thirty-day alert retention, daily encrypted index and
manager-state backups, and isolated restore. Those runtime outcomes remain gated.

The branch began at Desktop `b9eaeea8`. GitOps recovery PR249 owns replica
delegation, named metadata RBAC, graceful shutdown and native index snapshots.
IaC owns the dedicated Vault reader. Servarr PR362 supplies the self-contained
transport at `1c0dfb0d8e664be099485d48ed38a3ef5158da4d`, with file SHA256
`405be8c85afcf25553fb09a83ae96340a5913ff510b64d0fbb7dc11a901df4c4`.
Its private source is not vendored, placed in the Nix store, or fetched by a daily
job. Publication and runtime installation are separate actions.

## What changes and how it helps

After the reviewed manual-only host bootstrap installs the declared Python
interpreter, `just install-wazuh-backup-transport` uses the operator's GitHub
authentication and existing Kepler SSH/sudo route to materialize only that published script into a
root-private revision directory. It verifies the digest after installation and
refuses to overwrite a different release. The daily controller accepts only the
exact hash, root ownership and nonwritable release files/directories, executing
the verified bytes rather than reopening a mutable checkout.

One shared lock spans fresh native-index artifact validation, manager capture,
assembly, encrypted backup/readback and cleanup acknowledgement. Before quiesce,
the controller verifies authoritative Argo policy, healthy single-replica
managers, exact PVC/PV identities and CSI paths, and disk headroom. Durable intent
precedes scale-to-zero. Current-Pod markers must prove the official Wazuh stop
completed; only then may it snapshot `fast-pool/data`. Both managers recover
before exporting their two PVC directories. Filebeat data is retained without
claiming graceful Filebeat consistency.

Archives have a twelve-GiB aggregate cap; three unconsumed manager directories
block further quiesce. Cleanup addresses only the recorded task snapshot.
Transport writes root-owned public proof metadata outside the indexer PVC, after
encrypted publication and readback, before retiring consumed producer artifacts.
A backup-source timestamp reaches the existing textfile collector only after that
handoff succeeds. Failed systemd units remain visible through Alloy; a specific
missing/stale backup expectation is still required before daily scheduling.
The legacy textfile directory is host-user writable: its timestamp is presently
an operational signal, not protected evidence. Its trust policy must be settled
before enrolling daily alerts.

## Evidence and limits

The [test contract](test-contract.md) records observed REDs and the initial
implementation-first adapter limitation. Thirty-three focused tests now pass,
including preflight-before-quiesce, failure recovery, atomic private state,
materialization/hash/mode checks and truthful freshness. Synthetic Nix evaluation
proves disabled defaults, manual-only capture, independent recovery and pinned
arguments. Owner lint, formatting, structure and docs checks pass. The offline
Kepler toplevel dry evaluation passed after the normal owner command hit the known
Orion cache stall. Final integrated review and publication remain pending.

The first manager-only draft independently passed twenty-one tests and Nix
review. The Servarr transport independently passed historical restore, next-day
replacement and aggregate-copy regressions, plus actual disposable Restic 0.19.1
encryption/readback/wrong-password tests. None proves deployed Kubernetes scale,
real ZFS capture, Vault renewal, actual backup, or isolated Wazuh restore. No live
stop, snapshot, installation, credential write, backup or enrollment occurred.

## Recovery and activation gates

Boot/minutely rescue survives parent failure; same-boot deadlines use monotonic
time. Recovery intent older than 180 seconds stops the parent and restores both
named managers. The forty-minute overall job budget includes encrypted transport;
it does not extend the independent quiesce watchdog. Missing API credentials can
still prevent recovery, so an operator route and actual credential cycle must be
verified first. Keep capture and daily scheduling disabled until published
prerequisites, safe materialization, policy/identity proof, first encrypted backup,
isolated restore and freshness enrollment pass. Kepler-local encryption is the
accepted primary; Voyager expansion remains separate.
