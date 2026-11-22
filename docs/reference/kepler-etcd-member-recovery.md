# Kepler: preserve and recover one divergent etcd member

**Status:** Independently reviewed procedure candidate, 2026-11-22; preservation underway, member repair not executed or drilled.

## Outcome and evidence

The user requested “do fixes”. The intended outcome is agreement of the existing
three-member cluster without a total-cluster reset. Twice, at hash revision
64400845 and compact revision 64398344, cp-1 returned 1281518049 while cp-2 and
cp-3 returned 1906780554. cp-3 was leader, term 140; all services were active.
cp-2 had only recently passed startup after 57 restarts. Agreement identifies a
candidate recovery source, not proof that its historical contents are correct.
No alarms and a responsive Kubernetes API do not resolve that distinction.

The earlier host memory/kernel/ZFS faults and live w-1 image inspection failure
remain separate concerns. A brief quiet boot does not prove hardware integrity.
Abort this procedure if faults recur, the surviving pair loses quorum, or its
fixed-revision hashes cease to agree. Never stop a second control-plane member
while cp-1 is unavailable.

## Why preserve WAL and membership

Owner source sets cp-1 `clusterInit = true`, `serverAddr = null` in
[`k3s-cluster.nix`](../../modules/hosts/kepler/k3s-cluster.nix).
Deleting its whole database and starting normally risks a new singleton.
The [pinned K3s v1.36.5+k3s1 implementation](https://github.com/k3s-io/k3s/blob/v1.36.5%2Bk3s1/pkg/etcd/etcd.go)
recognizes an initialized member by `member/wal`, then uses the stored etcd
options with `ForceNewCluster=false`. Retain WAL, `name`, configuration and TLS.

The [etcd 3.6 corruption guide](https://etcd.io/docs/v3.6/op-guide/data_corruption/)
describes stopping a member, backing up its data, moving its `snap` directory
away, and starting it as an existing member to recover from the leader. Here
that directory is `/var/lib/rancher/k3s/server/db/etcd/member/snap`.
This is a bounded first attempt, not a guarantee: retained WAL or other host
damage can prevent recovery. Do not substitute member removal, full database
deletion, `--cluster-reset`, or disabled corruption checks after a failure.

## Preservation and verification before repair

Use the authenticated Kepler/guest access route in
[`just/k3s.just`](../../just/k3s.just), with individually verified SSH host keys.
Operate inside each selected guest as root; do not print tokens, certificates,
database keys, or values. The coordinator owns live execution.

1. Record cluster/member IDs, names, peer URLs, leader, term, alarms and endpoint
   health. Verify cp-2/cp-3 can perform linearizable health checks. Choose a fresh
   common revision from their status and compare `endpoint hashkv --rev=REV`
   with the same compact revision. Stop on disagreement or compaction races;
   choose a new common revision for a race, never compare latest hashes blindly.
2. Preserve existing scheduled snapshots before retention can prune them.
   Create a new consistent snapshot from each member separately, including the
   divergent member for evidence, with one selected endpoint per invocation.
   Use absolute verified client paths; the observed diagnostic client was 3.7.3
   against 3.6.14 servers. Prefer matching 3.6 tooling for offline restore checks;
   record the actual version instead of silently treating versions as identical.

   ```sh
   umask 077
   incident_dir=$(mktemp -d /run/kepler-etcd-preserve.XXXXXX)
   # ETCDCTL is the verified absolute client path; endpoint is this guest only.
   "$ETCDCTL" --endpoints=https://127.0.0.1:2379 \
     --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
     --cert=/var/lib/rancher/k3s/server/tls/etcd/client.crt \
     --key=/var/lib/rancher/k3s/server/tls/etcd/client.key \
     --command-timeout=120s snapshot save "$incident_dir/snapshot.db"
   "$ETCDUTL" snapshot status "$incident_dir/snapshot.db" --write-out=json
   ```

   Check available `/run` space before each snapshot. Metadata output may contain
   hash, revision, size and key count, never database contents. Snapshots taken
   sequentially may have different revisions; file hashes are not a replacement
   for fixed-revision endpoint agreement.
3. Include the matching server token in a private backup, never argv or logs.
   [K3s restore needs that token](https://docs.k3s.io/cli/etcd-snapshot).
   Use the existing public Sops age recipients from this repository's
   `.sops.yaml`. Either encrypt inside the guest before transfer, or stream the
   private bundle over authenticated nested SSH directly into local `age`
   stdin on Endeavour. SSH encrypts the transport; `age` encrypts before any
   destination file is written. The second route needs no guest age installation
   and must not use a plaintext local temporary file. Use mode-0700 directories,
   mode-0600 files, `pipefail`, no tracing and no plaintext terminal output.

   For the streaming route, the verified remote command emits only a binary tar
   of the exact snapshot and matching token; never redirect it separately:

   ```sh
   set -o pipefail
   umask 077
   # PRESERVE_SSH is an argv array for the verified nested SSH command.
   # RECIPIENTS is a private local file containing only approved public age recipients.
   # ENCRYPTED_DEST is a new incident-specific path; refuse an existing file.
   test ! -e "$ENCRYPTED_DEST"
   "${PRESERVE_SSH[@]}" | "$AGE" -R "$RECIPIENTS" -o "$ENCRYPTED_DEST"
   test -s "$ENCRYPTED_DEST"
   sha256sum "$ENCRYPTED_DEST"
   ```

   Treat any pipeline failure as an incomplete archive; preserve that diagnosis
   and use a new destination on retry. Verify decryption and expected tar member
   inventory privately before offline validation. For already encrypted remote
   bundles, compare ciphertext SHA-256 at both ends. Do not invent a new
   recipient or commit the bundle, even encrypted.
4. On Endeavour, validate an authorized private decrypted copy in an isolated
   directory: `etcdutl snapshot status`, then `etcdutl snapshot restore` into a
   fresh disposable data directory with a unique validation-only name/token and
   loopback peer URL. Do not start an etcd server or point it at production.
   Do not use `--skip-hash-check`. This verifies checksum and offline restoration,
   not application semantics, token decryption, or historical correctness.
   Retain the encrypted originals; clean private plaintext only after verification.

## One bounded member repair

Only after preservation succeeds, reconfirm cp-1's identity and cp-3 leadership.
If cp-1 became leader, pause and reassess instead of implicitly changing leaders.
The coordinator must reconcile any required destructive-action confirmation
against this exact scope; authorization does not include removing a member or
resetting the cluster.

1. Stop **only cp-1's `k3s.service`** through the owner access route. Verify its
   process/cgroup has stopped before copying state. Do not use `k3s-killall.sh`.
2. Make a complete offline, root-private copy of cp-1's etcd directory and
   associated identity/configuration; encrypt/export and verify it as above.
   This stopped copy, not a copy of a changing live directory, is the rollback
   evidence. Record file manifest/checksum metadata without dumping contents.
3. Confirm `member/wal` and `name` still exist. Move only `member/snap` to a
   unique retained sibling path outside `member`, on the same filesystem. Refuse
   an existing destination; never overwrite or remove prior evidence.
4. Start cp-1 once. Observe for at most five minutes. It must retain the existing
   cluster/member identity, catch up, and pass health. Recheck all three at a new
   shared revision/compact revision and verify matching hashes, three voting
   members, fresh node leases and no renewed host faults. Do not infer success
   from process activity or startup passing alone.
5. On failure, stop cp-1 to prevent an unbounded restart experiment; retain both
   its new attempt state and the original offline copy. Leave cp-2/cp-3 running
   if healthy, and report the exact failure before planning another method.

## Rollback and remaining risk

Before the first restart, reversing the directory move restores the original
layout, but also its known divergence. After restart, WAL may have advanced:
never combine the old `snap` with new WAL. A complete stopped-state backup is
required for any layout rollback, and must remain offline until reviewed; it is
not a safe database version to reintroduce automatically. No membership mutation
means no member-ID rollback is needed for this attempt. If the surviving pair
fails, stop improvising: coordinated cluster restore is a separate recovery
procedure with a stated data-loss window.

## Execution checkpoint and validation limits

The coordinator reports that actual preservation used the existing
`k3s etcd-snapshot save --name kepler-recovery-20261121` command on each CP.
Without the running service's snapshot-directory flags, these new files landed
in `/var/lib/rancher/k3s/server/db/snapshots`, not the scheduled virtiofs share.
All three snapshot metadata checks passed. Each selected snapshot and matching
`/tokens/token` was streamed over authenticated nested SSH into local age stdin;
only encrypted output reached Endeavour disk. The coordinator subsequently exported the existing scheduled snapshots as an
approximately 816 MB encrypted off-host archive; those historical copies remain
unvalidated. All three fresh bundles passed off-host validation: snapshot SHA-256
matched the source, matching tokens were present without display, and etcdutl
3.6.14 passed snapshot status and isolated restore with hash checks enabled.
No etcd server was started, and private plaintext validation directories were
removed. This proves format/checksum restoration, not historical correctness or
a production K3s restore.
These are coordinator observations, not executions by this document's author.

Matching local diagnostic binaries were obtained from the official etcd 3.6.14
Linux amd64 release. Both report version 3.6.14/API 3.6. Archive SHA-256
`ffe840ff9295808e88cce2794a18a5ac87f12a5203c8314d0bf6aa119b41bac5`
matched both the release SHA256SUMS and GitHub's asset digest before extraction.
No binary was installed into a live guest by this author.

The latest pre-repair checks at common hash revision 64426062 and compact
revision 64423411 returned cp-1 hash 693956178 versus cp-2/cp-3 hash 3536509858.
All three endpoint health checks passed; cp-3 remained leader, term 140. The
specific user approval for stopping cp-1, preserving its complete stopped state,
moving only `member/snap`, and one five-minute attempt remains pending. No
stopped-database backup or member repair has occurred. Silence is not approval.

The coordinator independently reviewed and accepted the bounded candidate after
preservation and applicable approval. `just docs-check` and `git diff --check`
passed. No additional procedure-review gate is introduced. No member repair or
live restore has run; record exact commands and outcomes in the incident receipt.
The existing total-loss runbook is not the targeted member procedure.
