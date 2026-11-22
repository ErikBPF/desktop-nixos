# Kepler: preserved etcd state and failed member recovery

**Status:** The approved bounded attempt failed on 2026-11-22; cp-1 is stopped. The prior snap-only procedure is withdrawn for this K3s configuration. No retry or alternative recovery is approved by this document.

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

## Why the source review was incomplete

At the failed attempt, cp-1 effectively used `clusterInit = true` and
`serverAddr = null` in
[`k3s-cluster.nix`](../../modules/hosts/kepler/k3s-cluster.nix).
Under that historical configuration, deleting its whole database and starting
normally risked a new singleton. The node specification retains those inputs
to preserve the bootstrap share, but the current temporary recovery candidate
overrides cp-1 with `mkForce`: effective `clusterInit = false`,
`serverAddr = "https://10.250.0.13:6443"`, no automatic boot start, one bounded
explicit startup and bootstrap
reconciliation disabled. See the [replacement proof and held candidate](../behaviors/k3s-bootstrap-reproduction/one-pager.md).
Source preparation does not establish what is active in the guest; verify the
actual closure before any startup. The history below explains the withdrawn
method, not the candidate's current effective settings.
The [pinned K3s v1.36.5+k3s1 implementation](https://github.com/k3s-io/k3s/blob/v1.36.5%2Bk3s1/pkg/etcd/etcd.go)
recognizes an initialized member by `member/wal`, then uses the stored etcd
options with `ForceNewCluster=false`. Retain WAL, `name`, configuration and TLS.

The [etcd 3.6 corruption guide](https://etcd.io/docs/v3.6/op-guide/data_corruption/)
describes stopping a member, backing up its data, moving its `snap` directory
away, and starting it as an existing member to recover from the leader. Here
that directory is `/var/lib/rancher/k3s/server/db/etcd/member/snap`.
The initial review checked the etcd existing-member path but missed an earlier
K3s bootstrap prerequisite. In the
[pinned bootstrap implementation](https://github.com/k3s-io/k3s/blob/v1.36.5%2Bk3s1/pkg/cluster/bootstrap.go),
an initialized server without a successful remote bootstrap first reconciles
bootstrap data using its local backend. At that attempt cp-1 had no join URL. Moving its `snap`
directory therefore prevents this reconciliation before normal etcd startup.
The general etcd purge guidance is not a complete executable recovery procedure
for this K3s configuration. Do not repeat the failed sequence or disable checks.

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

## Executed attempt: failed, no retry

After specific user approval and off-host snapshot validation, the coordinator
stopped only cp-1 K3s and preserved its complete stopped etcd directory, TLS and
token in a verified encrypted off-host archive. Only `member/snap` was moved to
`/var/lib/kepler-etcd-recovery/20261122-cp1/snap.before-recovery`; WAL and member
name were retained. One startup attempt failed at 01:51:26 UTC, before etcd
startup, during bootstrap reconciliation:

```text
stat /var/lib/rancher/k3s/server/db/etcd-tmp/member/snap/db: no such file or directory
```

The agreed stop-on-failure boundary was followed. cp-1 remains stopped with
`NRestarts=0` and `MainPID=0`; cp-2/cp-3 remain healthy. No retry, member removal,
cluster reset, or fallback was performed. The complete stopped archive receipts:

- Original archive SHA-256: `96f08bbb32a0d01d2ecd25aabaf31e1fbb93fe77bf32bf0702482a7aa9624834`.
- Encrypted archive SHA-256: `824e491407cb935005fcb45dec6ce0922972faf20a5872f47e76390b660d15f2`.
- Encrypted archive size: 460011450 bytes.

Keep the moved original snapshot and complete archive. Do not restore just the
old snapshot into potentially changed WAL. A next method requires review of
K3s bootstrap, membership, and rollback together; it is pending, not an implicit
extension of the failed attempt's approval.

## Maintenance entrypoint: contain reconciliation before stopping K3s

A later coordinator investigation found that cp-1's credential timer restarted
K3s through its reconciliation service's `Wants=k3s.service`. A service stop
alone was therefore insufficient. Through the authenticated owner guest route,
stop these units in order on **cp-1 only**:

```sh
systemctl stop k3s-bootstrap-secrets.timer
systemctl stop k3s-bootstrap-secrets.service k3s-manifest-reconcile.service
systemctl stop k3s.service
systemctl show k3s-bootstrap-secrets.timer -p ActiveState -p NextElapseUSecMonotonic
systemctl show k3s-bootstrap-secrets.service k3s-manifest-reconcile.service k3s.service -p ActiveState -p MainPID -p NRestarts
```

Require the timer inactive with no scheduled elapse and all reconciliation and K3s services without
running processes. A retained historical failed state/restart count is not a
new attempt; compare timestamps and PID state. Do not restart the timer while
the failed member is under maintenance. After a separately approved recovery
passes membership, fixed-revision hash and API health gates, explicitly start
the manifest and credential reconciliation services and then the credential timer. Do not start K3s implicitly by
starting the credential service. The
[maintenance-stop source fix](../behaviors/kepler-bootstrap-maintenance/one-pager.md)
removes that dependency from both credential and switch-driven manifest reconciliation and skips work while K3s is inactive; it does
not cancel work already running, so the ordered maintenance stop still applies.

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
The invocation did not include `--etcd-snapshot-dir` or `--data-dir`. The
coordinator located the new files in
`/var/lib/rancher/k3s/server/db/snapshots`; the same named files were absent from
the scheduled virtiofs share. File sizes, snapshot status and exported source
hashes were checked against those observed default-path files.

The earlier explanation that a standalone CLI does not inherit server flags was
incorrect. The [pinned CLI](https://github.com/k3s-io/k3s/blob/v1.36.5%2Bk3s1/pkg/cli/etcdsnapshot/etcd_snapshot.go)
sends a `/db/snapshot` request; it supplies a directory override only when that
option is set, otherwise using server defaults. Owner source configures the
running service with `--etcd-snapshot-dir=/etcd-snapshots`. Why the observed
runtime files were instead at the default path remains unresolved; do not infer
that the configured share is absent or rewrite the verified inventory to match
source. Locate and validate actual files before exporting. The reviewer on
head `06884ec` correctly challenged the causal explanation; the observed path
and backup validation are retained as execution evidence.
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

Earlier pre-repair checks at common hash revision 64426062 and compact
revision 64423411 returned cp-1 hash 693956178 versus cp-2/cp-3 hash 3536509858.
All three endpoint health checks passed; cp-3 remained leader, term 140. These were pre-attempt observations. The specific approval subsequently
arrived; the stopped-state preservation and failed single attempt are recorded
above. They do not authorize another attempt. A later pre-attempt gate used
hash revision 64451008 and compact revision 64448490: cp-1 returned 3531028427,
while cp-2/cp-3 returned 1875108299. These are historical pre-attempt checks,
not current hashes from the stopped cp-1.

The earlier independent review accepted an incomplete candidate; the actual
failure supersedes that source-only conclusion. Documentation checks cannot
validate a recovery algorithm. Next work is offline source review and a revised
concrete method, with cp-1 remaining stopped. The existing total-loss runbook is
not an automatic fallback.

## Matching diagnostic client staging

This preparation copies only the verified public `etcdctl` and `etcdutl` 3.6.14
clients into the immutable shared Nix store. It installs no service, changes no
profile/configuration, and performs no database operation. It follows the strict
copy and private GC-root pattern in `just cp1-stage-artifacts`, without changing
that recipe's five-artifact contract. Do not copy the `etcd` server executable.
The existing verified Kepler SSH identity remains mandatory.

Provenance: official `etcd-v3.6.14-linux-amd64.tar.gz`, obtained from the upstream
v3.6.14 release and checked against its published SHA256 list. Preserve the
archive and verification receipt. Expected SHA256 values:

- Archive: `ffe840ff9295808e88cce2794a18a5ac87f12a5203c8314d0bf6aa119b41bac5`.
- `etcdctl`: `dba085f02f045d6fc0cd59c533ef2a8dc922ad82418c0e538b194525c715450b`.
- `etcdutl`: `373c24bc46035055bd19f59e3933bbd8c7c479122636fa080853263f2decd021`.

The coordinator prepared this content-addressed store path locally using
`nix store add-path`, containing exactly the two public clients at mode 0555:
`/nix/store/mn2hcj16wbx88m2i5qshhxrx2g5lm2w9-cp1-recovery-etcd-tools-3.6.14`.
The source directory was private and removed after preparation. A local GC root
and hash receipt are retained under `~/.local/state/kepler-recovery/2026-11-22/`.
This preparation is not proof of remote staging or live recovery permission.

```bash
set -euo pipefail
client_store=/nix/store/mn2hcj16wbx88m2i5qshhxrx2g5lm2w9-cp1-recovery-etcd-tools-3.6.14
nix-store --check-validity "$client_store"
(
  cd "$client_store"
  test "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 2
  test "$(find . -mindepth 1 -maxdepth 1 | wc -l)" -eq 2
  printf '%s\n' \
    'dba085f02f045d6fc0cd59c533ef2a8dc922ad82418c0e538b194525c715450b  etcdctl' \
    '373c24bc46035055bd19f59e3933bbd8c7c479122636fa080853263f2decd021  etcdutl' \
    | sha256sum -c --status
)
test "$("$client_store/etcdctl" version)" = $'etcdctl version: 3.6.14\nAPI version: 3.6'
test "$("$client_store/etcdutl" version)" = $'etcdutl version: 3.6.14\nAPI version: 3.6'
NIX_SSHOPTS='-o BatchMode=yes -o StrictHostKeyChecking=yes -o ControlPath=none' \
  nix copy --to 'ssh://erik@192.168.10.230:2222?remote-program=sudo%20-n%20nix-store' "$client_store"
ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=yes -o ControlPath=none \
  erik@192.168.10.230 "sudo -n bash -s -- '$client_store'" <<'ROOT'
set -euo pipefail
test "$(hostname)" = kepler
client_store=$1
[[ "$client_store" == /nix/store/mn2hcj16wbx88m2i5qshhxrx2g5lm2w9-cp1-recovery-etcd-tools-3.6.14 ]]
nix-store --check-validity "$client_store"
cd "$client_store"
printf '%s\n' \
  'dba085f02f045d6fc0cd59c533ef2a8dc922ad82418c0e538b194525c715450b  etcdctl' \
  '373c24bc46035055bd19f59e3933bbd8c7c479122636fa080853263f2decd021  etcdutl' \
  | sha256sum -c --status
directory=/nix/var/nix/gcroots/cp1-recovery-etcd-clients-3.6.14
[[ ! -L "$directory" ]]
if [[ ! -d "$directory" ]]; then mkdir -m 0700 "$directory"; fi
[[ $(stat -c '%u:%a' "$directory") == 0:700 ]]
link=$directory/clients
if [[ -L "$link" ]]; then
  [[ $(readlink "$link") == "$client_store" ]]
else
  [[ ! -e "$link" ]]
  ln -s "$client_store" "$link"
fi
test "$("$client_store/etcdctl" version)" = $'etcdctl version: 3.6.14\nAPI version: 3.6'
test "$("$client_store/etcdutl" version)" = $'etcdutl version: 3.6.14\nAPI version: 3.6'
ROOT
printf 'Verified client store: %s\n' "$client_store"
```

Signature validation remains enabled. Stop if copying or any identity/hash/version
check fails; do not use `--no-check-sigs`. The guest shared store exposes these
absolute paths without guest package installation. Reverify path/hash/version in
the authenticated selected guest before its separately authorized health checks.
Do not infer why an earlier path disappeared. Preserve the task GC root until the
recovery evidence no longer depends on it; cleanup needs an explicit later scope.
