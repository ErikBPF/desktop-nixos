# S07 — disabled Kepler manager capture

## Outcome and purpose

This source prepares unattended capture of the two existing Wazuh manager PVCs,
with independent recovery and a pinned encrypted-backup handoff. It enables no
host service and creates no credential. The user's exact acceptance, “do as
recomendation”, covers thirty-day alert retention, daily encrypted index and
manager-state backups, and isolated restore. Those runtime outcomes remain gated.

The branch began at Desktop `b9eaeea8`, then rebased onto `3f0e7841`. GitOps recovery PR249 owns replica
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
implementation-first adapter limitation. Thirty-six focused tests now pass,
including preflight-before-quiesce, failure recovery, atomic private state,
materialization/hash/mode checks and truthful freshness. Synthetic Nix evaluation
proves disabled defaults, manual-only capture, independent recovery and pinned
arguments. Owner lint, formatting, structure and docs checks pass. The offline
Kepler toplevel dry evaluation passed after the normal owner command hit the known
Orion cache stall. Independent integrated review passed, including all three exact PV identities and Bound states. Publication follows these source gates.

The first manager-only draft independently passed twenty-one tests and Nix
review. The Servarr transport independently passed historical restore, next-day
replacement and aggregate-copy regressions, plus actual disposable Restic 0.19.1
encryption/readback/wrong-password tests. None proves deployed Kubernetes scale,
real ZFS capture, Vault renewal, actual backup, or isolated Wazuh restore. No live
stop, snapshot, installation, credential write, backup or enrollment occurred.

## Repair evidence (P2 review at `97e640c2`)

The review found two P2 gaps. First, recovery clears the durable intent before
archive export, so an explicit stop during export bypasses Python cleanup and
leaves `snapshot.json` plus `.incomplete-*` staging with no intent. The minutely
rescue then returned at the missing-intent guard forever, retaining snapshot COW
storage without bound. Rescue now calls a reclaim path when no intent survives.
That path takes `run.lock` and the export's `capture.lock` non-blocking, removes
`.incomplete-*` staging, and reuses the existing cleanup, which destroys only a
snapshot matching the owned-name regex and retains the record when ZFS existence
cannot be established. A live export holding either lock makes the path leave
storage untouched.

Second, the 150 s recovery/rescue unit budget was below the sequential deadline
path. The code deadlines are now named constants: 15 s stop, two 10 s API
requests, a 120 s readiness window plus one 20 s poll pair, 10 s snapshot
existence check and 30 s destroy, or 215 s worst case. The unit budget is 300 s,
leaving scheduling margin; the slow-success check reads the configured value and
drives `Cluster.wait` past its deadline with a fake clock.

Observed RED: three failures, two `AttributeError` for the absent reclaim path
and `assert 215 <= 150` for the budget (`/tmp/wazuh-capture-rescue-red.log`).
Observed GREEN: 47 focused tests pass (`/tmp/wazuh-capture-rescue-green.log`).
The checks use files and fake clocks only; no cluster, ZFS, host or credential
was accessed. The remaining runtime gates below are unchanged.

## Repair evidence (P2 review at `d594e93b`)

The review found that `Cluster.ready` accepted a terminating Pod: a Ready
condition with `metadata.deletionTimestamp` set. After an interrupted
scale-down, an old manager Pod can stay Ready while it terminates; scaling back
to one does not cancel deletion. `recover` then cleared `intent.json` before the
replacements were healthy, so later rescue ticks reclaimed storage and never
retried manager recovery.

`Cluster.ready` now requires a Pod with no `metadata.deletionTimestamp` before
it accepts the Ready condition. `preflight` and `wait_ready` both route through
that predicate, so capture verification and recovery apply one rule; the
duplicate deletion check in `preflight` is removed.

Observed RED: `test_recovery_waits_for_a_replacement_after_a_terminating_ready_pod`
failed with `assert [{'master': 1, 'worker': 1}] == [{'master': 2, 'worker': 2}]`,
showing intent was cleared on the first poll while the terminating Pods were
still served (`/tmp/opencode/wazuh-capture-terminating-red.log`). Observed GREEN: 48
focused tests pass (`/tmp/opencode/wazuh-capture-terminating-green.log`). The doc now
states the rescue staleness threshold as 1800 seconds (30 minutes), matching
`RESCUE_STALE_SECONDS`.

## Repair evidence (P2 review at `07f1038d`)

The review found that a normal service stop or deployment restart after
scale-down sends SIGTERM, which bypasses Python's `finally` block, and a
successful deactivation does not trigger `OnFailure`. Rescue then ignored the
same-boot intent until `RESCUE_STALE_SECONDS`, leaving both managers at zero;
a restarted capture refused the outstanding intent.

Rescue no longer returns early on a fresh intent. When the intent is not stale,
it still proceeds, and `run.lock` decides: a live capture holds the lock, so a
non-blocking acquisition failure exits 0 without touching the cluster; an
acquired lock means the capture is inactive, so rescue scales both managers to
one, waits for healthy non-terminating Pods and clears the intent on that tick.
The stale path is unchanged: rescue stops the parent first, then recovers. The
no-intent reclamation path and `KillMode` are unchanged; there is one recovery
path.

Observed RED: `test_rescue_recovers_a_fresh_intent_immediately_when_capture_is_inactive`
failed with `assert [] == ['scale:1', 'ready', 'clear', 'cleanup']`, showing
rescue still returned before recovery (`/tmp/opencode/wazuh-capture-fresh-intent-red.log`;
49 passed, 1 failed). Observed GREEN: 50 focused tests pass
(`/tmp/opencode/wazuh-capture-fresh-intent-green.log`). The second test holds
`run.lock` and proves a live capture is left alone. Tests use fake API, fake
storage and a temporary lock file only; no cluster, ZFS, host or credential was
accessed.

## Repair evidence (P2 review at `06614979`)

The review found that one shared `requires =
["wazuh-manager-scale-credential.service"]` covered all three modes. When the
credential agent failed activation, systemd also stopped or refused to start
capture through failure, recovery and the minutely rescue, even though the token
preserved at `/run/wazuh-manager-scale/token` by
`RuntimeDirectoryPreserve=restart` may still be usable. After an interrupted
scale-down, that left both managers at zero with every automatic restoration
path blocked.

Only capture now has a hard `Requires`. Recovery and rescue keep `After`
ordering, so systemd prefers a starting agent but starts them when the agent has
failed, and the mode reads the preserved token. The same rule now covers
`RequiresMountsFor`: capture requires `/fast` and `/bulk`; recovery and rescue do
not, because recovery only needs the state directory, token and API, and a
missing data mount must not block a manager scale-up. The synthetic evaluation
asserts the credential dependency and mount sets for all three modes and traces
the resulting sets; recovery still cleans up storage after the scale-up, so a
missing mount becomes a visible unit failure rather than a recovery block.

Observed RED: `nix eval --offline --impure --raw --file
tests/wazuh-manager-capture/evaluate.nix` failed at `assert !(builtins.elem
credential recovery.requires)` (`/tmp/opencode/wazuh-capture-deps-red.log`).
Observed GREEN: the same command prints
`S07_CAPTURE_EVAL_OK` and the dependency report
(`/tmp/opencode/wazuh-capture-deps-green.log`):

- capture: requires `wazuh-manager-scale-credential.service`; after
  `network-online.target`, credential service; mounts `/fast`, `/bulk`.
- recover: requires none; after `network-online.target`, credential service;
  wants `network-online.target`; no required mounts.
- rescue: requires none; after `network-online.target`, credential service;
  wants `network-online.target`; no required mounts.

Fifty focused tests pass. Owner lint, formatting and docs checks pass, and
`ripsecrets` reports no finding on the changed files. The checks evaluate Nix
only; no host activation, cluster, ZFS, credential or capture action occurred.

## Recovery and activation gates

Boot/minutely rescue survives parent failure; same-boot deadlines use monotonic
time. A fresh same-boot intent recovers immediately when the capture service is
inactive: rescue takes `run.lock` non-blocking, exits quietly while a live
capture holds it, and otherwise scales both managers back to one, waits for
healthy non-terminating Pods and clears intent on that tick. Intent older than
1800 seconds (30 minutes) is stale: rescue stops the parent first, then runs the
same recovery. The forty-minute overall job budget includes encrypted transport;
it does not extend the independent quiesce watchdog. Missing API credentials can
still prevent recovery, so an operator route and actual credential cycle must be
verified first. Keep capture and daily scheduling disabled until published
prerequisites, safe materialization, policy/identity proof, first encrypted backup,
isolated restore and freshness enrollment pass. Kepler-local encryption is the
accepted primary; Voyager expansion remains separate.
