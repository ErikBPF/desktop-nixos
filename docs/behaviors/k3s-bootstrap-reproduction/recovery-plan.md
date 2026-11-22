# cp1 replacement: ordered recovery boundary

**Status:** Prepared procedure, not live approval. The owning helper and its exact
published candidate manifest must pass review and preview before the coordinator
requests one new execution scope. No command in the disposable fixture is a
production recovery recipe.

## Preconditions before the irreversible step

1. Preserve the failed-method receipts and existing cp1 WAL/snapshot archives.
   The representative retained-WAL test failed; do not retry that method live.
2. Produce and verify fresh independent backups through the owning recovery
   recipe. Record the two surviving member IDs and cluster ID, healthy endpoints,
   no alarms, and matching hashes at one explicitly requested non-compacted
   revision. A historical checkpoint is not the execution gate.
3. Re-read cp1's exact etcd member ID, member name and peer URL. Confirm the
   Kubernetes Node UID is unchanged, deletionTimestamp is absent, and neither
   `etcd.k3s.cattle.io/remove` nor `etcd.k3s.cattle.io/removed-node-name` exists.
   Do not delete the Kubernetes Node: its controllers can remove the member and
   garbage-collect node-password state independently.
4. Verify trusted SSH keys, current guest closure/runner/boot ID and host
   current/profile expectations. The target is cp1 only. Confirm the candidate
   retains its kernel, initrd, network interfaces, disks and all shares, including
   bootstrap credentials. Its only intended service changes are the temporary
   recovery configuration and reviewed PR505 maintenance suppression.
5. Stop and verify suppression of both bootstrap timer and service, plus stopped
   K3s with MainPID=0. Stop `k3s-manifest-reconcile.service` and verify
   its MainPID=0 too; an already-running reconciler can outlive a new condition.
   Suppression must survive activation. Do not interpret a
   nonexistent unit or ineffective runtime mask as success. The candidate must
   render both bootstrap units disabled/masked, and its manifest reconciler must
   not pull K3s back in. The other control planes remain running.
6. Build and copy the exact reviewed guest closure/runner/registration through
   the owning helper. Inspect the rendered activation script for dry-activation
   support. The generated dry script honors dry user/group changes but still
   runs `install -d` on `/root` and `/home`, potentially normalizing metadata.
   Use static unit/hardware comparison before approval; include that bounded
   metadata effect in approval before running `switch-to-configuration
   dry-activate`. Review its output before the irreversible step. No whole-host switch.

## One separately approved replacement attempt

1. Recheck the above freshness/identity gates immediately before membership
   change. Two survivors provide quorum now but have zero failure tolerance while
   the third member is absent; stop if either becomes unhealthy or inconsistent.
2. Remove only the verified stopped cp1 member ID through a healthy survivor and
   confirm that exactly the original two survivors remain. This is irreversible
   for the old member; do not restart its old WAL as rollback.
3. On stopped cp1, quarantine the entire `server/db/etcd` directory to a new
   private, uniquely named destination. Preserve existing failed-state archives,
   `server/tls`, token files, `/etc/rancher/node` and agent state. Do not copy the
   old etcd name into the new directory. K3s must assign the new member identity.
   Do not use cluster reset or remove any other member.
4. Only now invoke the reviewed cp1-only activation helper once. The candidate
   joins cp3 with cluster initialization disabled and Restart=no. It has no
   multi-user boot start edge. The helper switches the closure, then explicitly
   starts K3s once; its five-minute service startup budget and outer bounds
   prevent an uncontrolled loop. That explicit start cannot precede approved
   member removal/quarantine.
5. Require the original cluster and survivor IDs, a new cp1 member ID, three
   voting members, healthy endpoints, no alarms, converged storage versions, and
   equal hashes at the same requested revision/compact revision. Verify the same
   Kubernetes Node UID, updated etcd member metadata and fresh readiness/leases.
   The agentless fixture proves the etcd primitive, not those Node controllers.
6. Persist only the reviewed cp1 runner through the owning helper after its
   success gates. Preserve the host current/profile and all sibling runtime
   identities. Capture receipt timestamps, source revision and checks.

## Failure and later cleanup

Any failed activation or verification leaves K3s stopped and bootstrap
suppression in place. Preserve quarantine and receipts; do not automatically
restore old etcd, recreate the removed member, switch the old guest closure, or
retry. Escalate for a fresh reviewed recovery choice.

After live recovery is independently accepted, a separate source cleanup must
restore the boot start edge, normal restart and bootstrap reconciliation policies using the PR505
maintenance-safe dependency behavior. Review whether to retain a healthy join
URL, then preview and activate that cleanup on cp1 only. Until then, the
single-attempt/no-reconciliation state remains an explicit operational risk.
