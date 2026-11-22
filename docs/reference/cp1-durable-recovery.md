# Revised cp-1 recovery sequence — held

**Status:** Held. The host build passed; exact-head source review and fresh
explicit live approval of this whole sequence remain pending. Source is published in
[PR509](https://github.com/ErikBPF/desktop-nixos/pull/509); publication is not
deployment approval. No live command below has been run for this procedure. No old `228`/cc8/a351 private manifest may be reused. Existing archives,
roots and receipts remain preserved. Stop at the first failed gate; no automatic
member-removal retry, old-WAL restart or return to the unsafe old host profile.

## 0. Bind reviewed source and expected artifacts

Desktop owns the supplemental `kepler-cp1-recovery` configuration. The source extends reconciled baseline
`a3f290e015eacce61e718f8596cdb6acc3716c7c` and selects the published guest from
`228bc67bf427fa1c4d33508f3f5967e2b1008d7a` through native `evaluatedConfig`.
Supplemental-only boot counting is disabled. These are source pins, not permission
to execute the old manifest. Use the final reviewed published host revision,
not a mutable working tree or the ordinary `kepler` output.
The existing owner deployment recipe takes the verified fleet IP explicitly:
`192.168.10.230`, SSH erik on port 2222. Existing strict host-key verification
remains an independent prerequisite; the address is not proof of identity.
The supplemental deploy-rs node is withdrawn; do not select a deploy-rs route.

In its exact clean owner checkout, record `git rev-parse HEAD` and obtain expected
values from these source outputs in the final reviewed published checkout:

```bash
nix eval --raw .#nixosConfigurations.kepler-cp1-recovery.config.system.build.toplevel
just cp1-artifact-metadata 228bc67bf427fa1c4d33508f3f5967e2b1008d7a
```

Evaluation and build passed for the expected running AND persistent host:

`/nix/store/492mc5ylp5zjk6qmflyxw0jgayjwk4zz-nixos-system-kepler-26.11.20261115.5c3cda7`

The local evaluation receipt is `/tmp/kepler-host-containment-final-green.log`;
this is a workstation receipt, not a portable prerequisite or proof of live
deployment. Re-evaluate against the final published head and reject drift.
Extract the exact installer unit/script and systemd executable from the built
host. Preserve its unit/script hashes, guest runner/toplevel and bootloader
configuration. The existing `nixos-rebuild switch` owner route selects the host
toplevel directly as the persistent system profile, not an activation wrapper.

The built wrapper
`/nix/store/aq1z3l8qmpzgwmgyczix15146ji43002-activatable-nixos-system-kepler-26.11.20261115.5c3cda7`
is **withdrawn and was never executed**. Its `deploy-rs-activate` runs
`sed -i '/^default /d' /boot/loader/loader.conf` after switching, removing the
exact safe default required here. This finding supersedes prior deploy-rs
completion instructions; the host `492mc5…` artifact itself is unchanged.

The reviewed guest artifacts are `9m1zvc…`
and `s226dm…`; require full path equality with the published metadata. Verify
unchanged host kernel, relevant hardware, Syncthing/credentials and five sibling
guest closures before live approval. No invented pending closure paths.

## 1. Establish baseline containment

Through the existing verified owner SSH routes, reobserve Kepler boot ID,
running/persistent host profiles, six VM PIDs/start timestamps and current/booted
runner links. In cp-1, require unchanged guest boot ID/old closure and K3s,
credential service, credential timer and manifest reconciler all stopped with
MainPID zero (service state inactive/failed; timer inactive). Record existing
mask/enabled states. Any required maintenance stop is an explicit part of the
new approved procedure; do not let a discovery check start K3s. Preserve prior
stopped-state backup/quarantined snapshot evidence and confirm free space.

## 2. Owner host preview, then host deployment

Only after the whole live procedure is approved, from the pinned owner checkout:

```bash
just deploy-preview kepler-cp1-recovery 192.168.10.230
```

Inspect the complete preview. Accept only the independently reviewed host delta:
the cp-1 native installer selects the safe guest, plus the specific bootloader
containment change and reviewed credential reconciliation. Reject extra service
stops/restarts, VM restarts, sibling changes or unrelated configuration drift.
Dry activation is not filesystem-write-free; upstream directory metadata may
be normalized. It performs no guest activation, but remains within live approval.

If the preview matches, run exactly:

```bash
just deploy kepler-cp1-recovery 192.168.10.230
```

Require full owner command completion with exit zero, then independently
re-establish authenticated SSH and verify the host, installer, profile and
bootloader gates below. This route has no deploy-rs canary confirmation or
automatic rollback. A successful command alone does not prove containment;
transport loss, partial activation or any mismatch keeps removal blocked.
Do not automatically return to the old host profile, restart old WAL, manually
edit loader.conf, or compensate with a symlink. Recovery from a failed host
switch requires an explicit reviewed action while cp-1 remains stopped.

## 3. Prove durable host selection before removal

Apply the separately reviewed read-only gate in
[boot containment check](cp1-boot-containment-check.md), filled from the built constants:

- Running host and persistent system profile both match `492mc5…`; loaded
  installer FragmentPath, immutable ExecStart executable/argv and script hash
  match source, with no unexpected drop-ins or daemon-reload discrepancy.
- Native installer has selected the safe current runner and matching toplevel;
  the booted runner and all six running VM identities remain unchanged. Sibling
  selected runners also remain unchanged. The host boot ID is unchanged.
- Using the candidate's reviewed `bootctl`, inspect `list --json=short` and
  `status --no-pager`, actual ESP/XBOOTLDR loader.conf and selected entry. The
  exact next default `init=` must resolve to the safe host closure, with no
  counter/wildcard/preferred/EFI one-shot/default/sysfail route automatically
  selecting the unsafe old installer. Retained old entries are not safe rollback
  choices after removal. Source disablement alone is not proof of the live ESP.
- Recheck cp-1 still runs the old guest closure with all recovery units stopped
  and PID zero. Safe next-boot selection and current running guest are distinct.

Any failure blocks removal. Do not perform raw bootloader edits/blessing or a
manual post-health `current` pin. No actual reboot is proposed; isolated ordering
fixtures cover only their translated systemd semantics.

## 4. Refresh the private manifest; preview the guest before destructive work

Create a NEW private mode-0600 helper manifest from published guest metadata and
fresh post-host-containment observations. Record the new host running/persistent
baselines and selected current runner. `baseline.runner` can equal the candidate
runner while `baseline.guestCurrent` remains old. `guestProfile: "absent"` is valid
only if neither a file nor a symlink exists. Preserve exact guest boot ID,
verified known-hosts file/hash, source pin and old guest hardware provenance.
Bind the separate host-containment receipt; the helper does not enforce it.

Then run through the merged owner recipe, using the new actual remote filename:

```bash
just cp1-activate "$REMOTE_MANIFEST" preview
```

Source validation: the helper verifies both identities, exact built-unit delta,
boot masks/no automatic K3s boot edge, and stopped recovery units, then calls only
`switch-to-configuration dry-activate` (60-second bound). Preview exits before
registration loading, guest profile creation, switch or explicit K3s start.
It may normalize `/root` and `/home` metadata. Inspect output and recheck stopped
units/unchanged boot and closure; reject unexpected service actions. Passing
preview is not etcd recovery and is not approval for the next step.

## 5. Fresh survivor backup, equality and exact member/Node gate

With cp-1 still stopped, refresh healthy cp-2 and cp-3 backups separately using
verified absolute ETCDCTL/ETCDUTL and one local TLS endpoint per invocation:
`endpoint health`, `endpoint status`, `alarm list`, `member list`, then
`snapshot save` with a 120-second bound and source SHA256. Check free space first.
Use the [owner preservation reference](kepler-etcd-member-recovery.md)'s authenticated nested-SSH stream
into local age encryption with existing approved Sops recipients; no plaintext
local spool, new recipient, secret output or standing credential. Independently
read back/decrypt privately, compare source snapshot hashes, verify matching
token inventory, and run matching etcdutl3.6.14 status plus isolated restore with
hash checking enabled. Never start a server during validation.

Choose a fresh common non-compacted REV. On each survivor, the verified client
array runs `endpoint hashkv --rev="$REV" --write-out=json`. Require identical
returned hash revisions, compact revisions and hashes; both healthy/no alarms,
original cluster and survivor IDs. Preserve integer IDs losslessly with Python,
not floating-point JSON conversion. Recheck exact old cp-1 member ID/name/peer
URL and Kubernetes Node UID, no deletionTimestamp and no remove/removed-node-name
annotations. Keep these exact values in the new private receipt, not placeholders.

## 6. Remove once, read back, then quarantine

On verified cp-3 only, using the bound authenticated client array and exact
OLD_MEMBER_HEX from the fresh receipt, re-read membership immediately before:

```bash
"${etcd[@]}" member remove "$OLD_MEMBER_HEX" > "$receipt/member-remove.txt"
"${etcd[@]}" member list --write-out=json > "$receipt/members-after.json"
```

Require exactly the two original survivors and absence of the old member; no
unexpected member/learner. Never blindly retry removal after an ambiguous result.
Only then, on verified stopped cp-1, use this preserved quarantine operation
under the new whole-sequence approval (the old appendix remains held):

```bash
set -euo pipefail
umask 077
test "$(hostname)" = cp-1
for unit in k3s k3s-bootstrap-secrets k3s-manifest-reconcile; do
  test "$(systemctl show "$unit.service" -p MainPID --value)" = 0
  state=$(systemctl show "$unit.service" -p ActiveState --value)
  case "$state" in inactive|failed) ;; *) exit 1 ;; esac
done
test "$(systemctl show k3s-bootstrap-secrets.timer -p ActiveState --value)" = inactive
parent=/var/lib/rancher/k3s/server/db
test -d "$parent/etcd" && test ! -L "$parent/etcd"
quarantine="$parent/etcd.before-member-replacement.$(date -u +%Y%m%dT%H%M%SZ)"
test ! -e "$quarantine" && test ! -L "$quarantine"
mv -T -- "$parent/etcd" "$quarantine"
sync -f "$parent"
test ! -e "$parent/etcd" && test -d "$quarantine/member/wal"
```

Record that destination privately. Preserve all TLS, node-password, token and
prior archive paths. The old-member directory is evidence, never automatic
restart rollback.

## 7. One helper activation and bounded outcome

```bash
just cp1-activate "$REMOTE_MANIFEST" activate
```

The existing helper repeats its 60-second dry activation before loading
registration/creating the first guest profile; the new approval must include
that repetition after removal. It switches guest configuration (120 seconds),
verifies new closure, unchanged boot ID, loaded Restart=no, bootstrap masks and
exact cp-3 join command without cluster-init, then explicitly starts K3s ONCE
(330 seconds enclosing the 300-second service timeout; outer SSH 660 seconds).
It checks active state/boot/closure and unchanged host/runner afterward.

A failed start invokes bounded stop and checks PID zero. A pre-start failure
leaves start unattempted. Transport loss or ambiguous containment is a hard
stop requiring verification; no old host/WAL rollback, repeated member removal,
re-enrollment or alternative K3s start. Preserve all diagnostic receipts.

## 8. Recovery gate, then KEDA and Wazuh

Require three healthy voting members, no learners/alarms, original cluster and
survivor IDs, a new cp-1 ID, matching storage version and a fresh common
fixed-revision hash/compact revision across all three. Verify Kubernetes Node
identity/password compatibility, API readiness and preserved host/runner/sibling
identities. New membership or API availability alone is insufficient. There is
NO post-health manual runner-persistence step: durable selection preceded removal.

Only after that gate, the coordinator refreshes exact heads/CI/reviews and merges
KEDA PR251, observes its rollout/readiness and w-2 capacity, then merges Wazuh
PR250 and observes indexer startup/readiness. Both Argo applications auto-sync;
merge is deployment. Use existing owner GitOps merge/sync procedures, no forced
global sync. This procedure does not assume a future merge SHA or successful rollout. Retain
recovery safeguards until separately reviewed cleanup; report any remaining
hardware/backup/notification limitations rather than declaring full recovery.
