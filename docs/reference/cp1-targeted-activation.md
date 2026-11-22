# Targeted cp-1 recovery activation

**Status:** Source preparation only. Immutable build/copy and task GC roots are authorized preparation. Fresh approval of the complete member-replacement method is required before guest dry activation, member removal or activation. A successful switch does not prove etcd recovery.

## Purpose and boundaries

The recovery candidate preserves the guest kernel, initrd, interfaces, volumes and
shares while joining cp-3 without `cluster-init`. K3s gets `Restart=no` and a
five-minute startup timeout. Bootstrap service/timer are disabled in source; the
manifest reconciler loses its K3s start dependency and gains an active-service
condition. These are the only allowed unit changes.

The helper runs only on Kepler and addresses only cp-1. It never switches Kepler,
restarts a VM, removes an etcd member, moves WAL/backend files, or restores an old
configuration. The approved replacement procedure must remove the failed member
and preserve/quarantine its state **before** activation, because activation starts
K3s. A new cp-1 member ID is expected; survivor IDs and cluster identity must remain.

## Prepare exact artifacts and observations

After candidate publication, `just cp1-stage-artifacts REVISION` builds exactly the
cp-1 toplevel, runner, Nix package and closure registration from that full commit.
It copies through authenticated, strictly verified SSH with normal Nix signature
checks, then creates root-owned task GC links under
`/nix/var/nix/gcroots/cp1-recovery-REVISION`. Neither Kepler system profile changes.
GC roots remain until reviewed cleanup; copying alone is not persistent GC safety.

`just cp1-artifact-metadata REVISION` exports evaluated paths and hardware. Run it
for the reviewed baseline and candidate. The actual nested attribute is
`nixosConfigurations.kepler.config.microvm.vms.cp-1.config.config`.

Build a private reviewed `/tmp/cp1-activation-NAME.json` on Kepler with this shape:

```json
{
  "sourceRevision": "FULL_CANDIDATE_COMMIT",
  "knownHosts": "/absolute/preverified/cp1-known-hosts",
  "knownHostsSha256": "SHA256_OF_THAT_FILE",
  "baseline": {
    "hardware": {},
    "hostCurrent": "OBSERVED_KEPLER_RUNNING_CLOSURE",
    "hostProfile": "OBSERVED_KEPLER_PERSISTENT_CLOSURE",
    "guestCurrent": "OBSERVED_CP1_RUNNING_CLOSURE",
    "guestProfile": "OBSERVED_CP1_SYSTEM_PROFILE",
    "guestBootId": "OBSERVED_CP1_BOOT_UUID",
    "runner": "OBSERVED_CP1_CURRENT_RUNNER",
    "bootstrapTimerState": "OBSERVED_IS_ENABLED_STATE",
    "bootstrapServiceState": "OBSERVED_IS_ENABLED_STATE"
  },
  "candidate": {}
}
```

Replace `baseline.hardware` and `candidate` from the two source exports; replace
all observation placeholders with fresh read-only evidence. Require baseline
exported toplevel/runner to match the running guest and recorded runner. Do not
invent paths or infer SSH trust from a live disk read that reports errors. Record
existing bootstrap mask states so a later release cannot silently unmask a unit
that was already intentionally masked.

## Preview, activation and stop boundary

Before preview, require the four units `k3s.service`,
`k3s-bootstrap-secrets.timer`, `k3s-bootstrap-secrets.service` and
`k3s-manifest-reconcile.service` stopped with MainPID zero. Their maintenance stop
belongs to the approved recovery procedure. Confirm surviving etcd quorum/health,
matching fixed-revision hashes and the preserved failed-state archives.

Run `just cp1-activate MANIFEST preview`; inspect its real dry-activation output.
This upstream dry activation does not switch services, but its user-management
script may normalize `/root` and `/home` directory metadata; it is not promised
to make zero filesystem writes. Include that bounded behavior in live approval.
Reject unexpected service actions outside the four reviewed units. After explicit
approval, `just cp1-activate MANIFEST activate` loads guest registration, selects
the new guest profile and switches only that guest. The switch is bounded at
360 seconds; the SSH operation has a 540-second outer budget for preview and
cleanup. Signal/failure handling attempts a bounded stop and checks K3s PID zero;
transport loss can prevent confirmation and must be treated as uncontained until
verified. No automatic old-etcd restart or bootstrap unmask occurs.

The helper asserts unchanged Kepler running/persistent profiles, cp-1 current
runner and guest boot ID. It intentionally leaves the host runner unchanged.
After replacement health, alarms, survivor/member IDs and fixed-revision hashes
pass, stage the reviewed current runner through the post-health owner step included in the approved procedure.
Until then, do not reboot cp-1: its boot runner still selects the prior closure.

## Explicit post-health runner persistence

Only after approval of the complete procedure and verified replacement health, run these commands
on Kepler as root with the same reviewed manifest. They alter only cp-1's next-boot
runner. Record the current `booted` target before approval and supply that exact
value as `EXPECTED_BOOTED_RUNNER`; do not infer it from `current`.

```bash
set -euo pipefail
manifest=/tmp/cp1-activation-NAME.json
: "${EXPECTED_BOOTED_RUNNER:?recorded booted runner required}"
old=$(jq -er '.baseline.runner' "$manifest")
new=$(jq -er '.candidate.runner' "$manifest")
revision=$(jq -er '.sourceRevision' "$manifest")
[[ "$revision" =~ ^[a-f0-9]{40}$ ]]
[[ "$new" =~ ^/nix/store/[a-z0-9]{32}-microvm-cloud-hypervisor-cp-1$ ]]
[[ $(readlink -e /run/current-system) == "$(jq -er '.baseline.hostCurrent' "$manifest")" ]]
[[ $(readlink -e /nix/var/nix/profiles/system) == "$(jq -er '.baseline.hostProfile' "$manifest")" ]]
directory=/fast/microvms/cp-1
[[ $(readlink -e "$directory/current") == "$old" ]]
[[ $(readlink -e "$directory/booted") == "$EXPECTED_BOOTED_RUNNER" ]]
roots=/nix/var/nix/gcroots/cp1-recovery-$revision
[[ -d "$roots" && ! -L "$roots" && $(stat -c '%u:%a' "$roots") == 0:700 ]]
if [[ -L "$roots/previous-runner" ]]; then
  [[ $(readlink "$roots/previous-runner") == "$old" ]]
else
  ln -s "$old" "$roots/previous-runner"
fi
[[ $(readlink -e "$new/share/microvm/system") == "$(jq -er '.candidate.toplevel' "$manifest")" ]]
link=$directory/.current-recovery-$revision
[[ ! -e "$link" && ! -L "$link" ]]
ln -s "$new" "$link"
mv -T "$link" "$directory/current"
[[ $(readlink -e "$directory/current") == "$new" ]]
[[ $(readlink -e "$directory/booted") == "$EXPECTED_BOOTED_RUNNER" ]]
[[ $(readlink -e /run/current-system) == "$(jq -er '.baseline.hostCurrent' "$manifest")" ]]
[[ $(readlink -e /nix/var/nix/profiles/system) == "$(jq -er '.baseline.hostProfile' "$manifest")" ]]
```

Do not modify the existing `old` link or `booted` link, restart the VM, release
bootstrap masks, or delete GC roots automatically. A future host deployment must
include the reviewed replacement source so it does not restage the old runner.

## Evidence and limits

Command-level fixtures cover preview, identity/PID/drift rejection, signal and
failed-switch containment, finite budgets, strict manifest values and exact unit
changes. The unit comparator also passed against actual built baseline `5dd7…`
and candidate `xp0g…`; source-disabled bootstrap units resolve to `/dev/null`.
REDs are in `/tmp/cp1-{commands,pid-budget,active-service,unit-delta,condition-path}-red.log`.
These are preparation checks, not live activation or persistent recovery proof.

### Staging output correction

The first owner staging attempt stopped before copying: Nix selected the Nix
package's manual output as well as its executable output, producing five paths
instead of the required four. Selecting `c.nix.package.out` explicitly produced
the four reviewed artifacts. The failed output-count guard caused no remote
mutation; the actual cached build confirmed the corrected output set.

The post-staging read-only check exposed an incorrect default runner directory
in the first helper draft. Kepler's owning source explicitly sets
`microvm.stateDir = "/fast/microvms"`; the current and booted links there both
resolve to the retained `324az74...` runner. The guard and persistence procedure
now use that exact directory, and immutable metadata exports and validates it.
The corrected host-path fixture failed before the repair. No guest operation
ran against the incorrect path; the helper would have stopped at preflight.

Root's read-only guest preflight also confirmed the normal microVM boot has no
`/nix/var/nix/profiles/system` entry. Record `guestProfile: "absent"` only when
both the file and symlink are absent. The guard rejects unexpected appearance
or dangling links; activation creates the first guest profile. Existing profiles
still require the exact observed store path. This exception never applies to
the host profile. Disposable actual-file tests cover all six combinations.

### Authorized artifact staging receipt

At 2026-11-22 02:46 UTC, the owner staging recipe completed for candidate
`7daee157e729dec33b250e2dfff39998bfea185b`. The four reviewed artifacts are retained
under `/nix/var/nix/gcroots/cp1-recovery-7daee157e729dec33b250e2dfff39998bfea185b`
(root:root, mode 0700). Normal Nix signature verification remained enabled.
Kepler's boot ID, running `zi7mrr...` closure and persistent `mhd9qc...` wrapper
were unchanged. Current and booted cp-1 runners still resolve to `324az74...`.
The exported candidate metadata, now including the source-owned state directory,
has SHA-256 `dae5fa3806e2f2ed9b41776787e2818c78b2035a798877ed1e283d6ff367a0e7`.
No guest preview, membership operation, activation or runner persistence was
performed. These remain within the concrete approval gate above.

### Declared comparator runtime

Kepler's interactive PATH has no Python. The first shell draft therefore would
have stopped before guest SSH. The helper now stages the candidate package set's
Python executable output as a fifth GC-rooted artifact, exports its exact path,
and invokes that path for unit comparison. An empty-PATH command regression
failed with `python3: command not found` before the fix. No global host package
installation is required; the guest closure is unchanged. Earlier four-artifact
receipts remain historical evidence, not the complete final runtime contract.

The first hosted lint run also caught the owner's command-layout contract:
`--max-jobs 0` must occur on the `--builders` line or immediately after it.
Moving the already-present flag onto that line preserves build behavior and
passes the unchanged contract. The combined helper and owner recipe suite now
passes 78 tests; the helper alone passes 39. The comparator uses Python isolated
mode (`-I`) to ignore inherited user-site and Python environment overrides.
