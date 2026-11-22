# Exact-version K3s recovery reproduction

**Status:** Retained-WAL recovery rejected; disposable explicit member replacement
passed independent review. A temporary cp1-only source candidate is prepared.
Live recovery requires a new approval and the reviewed owning helper.

## Outcome and why

Human seed: `continue` (following `do fixes`). The user asked to continue fixes after cp-1 could not restart following removal
of its embedded-etcd snapshot directory. Source inspection suggested adding a
healthy peer's HTTP bootstrap URL might restore bootstrap data while retaining
the existing member identity. The first disposable run appeared to support that
approach, but independent review identified a missing boundary: its WAL still
contained history from initialization. Production's first retained segment was
`0446`, so replay from index zero was unavailable.

The strengthened run forced actual 64MiB WAL rotation and pruning. It reproduced
the exact missing `etcd-tmp/member/snap/db` bootstrap failure, then showed that
adding the peer URL only moved the failure: etcd fatally reported that no WAL
file matched snapshot index zero. That method is rejected for the observed
retained-history state. The earlier successful run is preserved as limited
evidence, not presented as permission for live recovery.

## Fixture boundary

The fixture uses cached K3s **1.36.5+k3s1** and asserts the embedded server's
**etcd 3.6.14** status. The cached etcdctl 3.7.3 executable is a client only.
The root flake input resolves nixpkgs `5c3cda7610193a82ba555e178e80de6667ae03de`;
reading an unrelated lock-node label would incorrectly identify another version.
The existing NixOS HA test needed 989 unrealized derivations, so the coordinator
approved the smaller process fixture.

Three servers run inside unprivileged Bubblewrap user, mount, PID and network
namespaces, with independent child network namespaces and no default route.
Host home, credentials and kubeconfig are absent; `/etc`, `/var`, `/run` and
`/tmp` are fresh. Only the private fixture receipt directory is writable outside
the sandbox, and the Nix store/tool paths are read-only. A user-systemd scope
caps the campaign at 8GiB memory and four CPU equivalents; the harness caps each
complete run at 600 seconds and stops its owned processes in cleanup.

Maturity means 450 synthetic one-MiB writes, raft snapshot count 100, catch-up
window 10, actual oldest WAL sequence greater than zero, and MVCC compaction.
The fixture never uses cluster reset, production routing or production data.

## Evidence and decisions

The first run, `/tmp/k3s-bootstrap-reproduction-iuplfl2_`, retained identities and
matched revision 827/hash 1152013965, but retained genesis history and sampled
cp-1 storage version too early. Its result is explicitly superseded for live
applicability. The representative rejected run is
`/tmp/k3s-bootstrap-reproduction-bud7swv7`; its frozen reproducer SHA256 is
`27f70869ba4864800fee1137b7d20080800de71c55cf0b95f98618f3ee694425`.
Both preserve private logs and identity/hash receipts. Infrastructure setup probes
are not behavioral REDs.

The successful replacement run `/tmp/k3s-bootstrap-reproduction-0ys6_elo`
preserved cluster ID and both survivors, assigned a new cp1 ID, and converged all
storage versions to 3.6.0. All three hashes were 1203773923 at requested revision
1215, compact revision 980, with healthy endpoints/no alarms; peer snapshot
transfer and promotion were observed. The coordinator independently checked these
receipts. This hypothesis removes only the exact stopped member
ID after verifying its name/peer URL and both survivors' health. It quarantines
the entire synthetic etcd directory, preserves TLS and token file hashes, and
joins through cp3 with cluster initialization disabled. Success must preserve the
cluster and survivor IDs while assigning a new cp1 member ID, establish three
voters, match hashes at the requested revision with equal compact revisions,
report healthy endpoints/no alarms, and converge storage versions after a bounded
stabilization period.

## Candidate and remaining gates

The temporary Nix candidate overrides only cp1's effective K3s settings: no
cluster initialization, join through cp3, Restart=no and a five-minute startup
budget. Its boot start edge is removed; bootstrap service/timer are disabled. The original node specification
and bootstrap share remain unchanged. A Nix assertion failed before these edits
and passed afterward. The maintenance suppression fix in PR505 is a prerequisite;
the owning helper must permit its exact manifest-reconciler change as well.
The targeted build passed: boot-guard closure `9m1zvcbinrv8396j6jzvjw9ncx7pk4q4`,
runner `s226dm43kyklikzpbg64aj1vwhlgydhb`. Actual bootstrap units resolve to
`/dev/null` and the built multi-user K3s symlink is absent; five sibling outputs and cp1 hardware match the PR505 baseline.
Lint, formatting, docs links, Nix assertions and actual commit hooks passed.

The helper explicitly starts K3s after switching: approved member removal and
full-directory quarantine must happen first. The [ordered recovery plan](recovery-plan.md)
defines that boundary. Do not deploy the whole host or activate siblings.
The absent boot start edge, Restart=no and disabled reconciliation remain
temporary reliability limitations
until a separately reviewed cleanup restores them after recovery; a successful
join alone does not close the incident.

The process fixture has no agents, Kubernetes Node UID or node-password
controller: those production identity checks require separate source review and
fresh preflight. Any member removal permanently invalidates the old WAL as a
rollback target; the two survivors temporarily have no fault tolerance. A live
member replacement requires a new concrete approval, validated backup/quorum,
maintenance suppression, a reviewed single-member activation path and explicit
stop behavior. No production candidate is declared ready by this document.

Hosted review first corrected a historical source description. Its second
finding exposed the retained boot start edge: Nix assertion RED preceded the
cp1-only `wantedBy = []` fix. Immutable copy/GC roots never activate a runner;
the guarded risk is later installation and boot of this temporary candidate.
No live action or new recovery-primitive run occurred.


## Preview guard repair — 2026-11-22

The coordinator's approved guest preview stopped before dry activation because
an inactive systemd timer has no MainPID property. Existing command fixtures
incorrectly supplied PID zero for timers. A realistic empty timer-property
response produced assertion-failing RED; the minimal guard checks timer
inactivity separately and keeps service inactivity/PID-zero checks. Failed
property reads and missing service PIDs reject execution. The targeted helper
suite passes 57 tests, including active/failed/unknown timers and read failures.

This is a source-only repair awaiting review and renewed successful preview.
The coordinator reports host containment already deployed, with guest K3s still
stopped and no member removal or quarantine. Fixture success does not establish
production recovery or permit skipping any ordered recovery gate.
