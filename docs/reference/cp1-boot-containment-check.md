# cp-1 pre-removal boot containment check

**Status:** Held for completed host build, exact-head review and fresh live
approval. No command in this check has been run on Kepler. Use it only within the
[revised recovery sequence](cp1-durable-recovery.md), never as standalone approval.
This is a read-only gate after a separately authorized owner deployment, not a
replacement deployment recipe or authorization for removal.

Pinned microvm host/default.nix selects evaluatedConfig before config, generates
install-microvm-cp-1 to run `ln -sTf RUNNER current` and set `toplevel`, and runs
that installer on declarative rebuild/boot. Therefore checking current alone is
insufficient. The safe installer must be both loaded now and retained in the
persistent host deployment. The existing helper can remain unchanged if this
independent gate is completed and its manifest records the new host baselines.

Before filling variables, the owner must independently verify the published
kepler-cp1-recovery output, native generated installer script and unit, preserved
Syncthing/credential changes, all sibling closures, and restartIfChanged=false.
Capture exact expected running closure, persistent activatable wrapper, installer
unit target, and installer script SHA256 from those immutable artifacts. The evaluated expected host and wrapper paths
are recorded in the [sequence](cp1-durable-recovery.md); their build is pending. Do not
infer these expected values from the live host under test.

Wait for the owner deploy-rs operation and its confirmation/automatic-rollback
protocol to finish successfully before opening the removal gate. No pending
rollback may restore the old installer after this check. The owner must identify
and verify the pinned deploy-rs completion semantics; this check defines no
rollback-unit name or substitute deployment implementation.

The following proposed read-only assertions run on Kepler through the verified
owner SSH route, with exact reviewed constants supplied privately:

```bash
set -euo pipefail
: "${EXPECTED_HOST_BOOT:?}" "${EXPECTED_HOST_CURRENT:?}" "${EXPECTED_HOST_PROFILE:?}"
: "${EXPECTED_INSTALLER_UNIT:?}" "${EXPECTED_INSTALLER_SCRIPT:?}" "${EXPECTED_INSTALLER_SHA256:?}"
: "${EXPECTED_RUNNER:?}" "${EXPECTED_GUEST_TOPLEVEL:?}" "${EXPECTED_BOOTED_RUNNER:?}"
test "$(hostname)" = kepler
test "$(cat /proc/sys/kernel/random/boot_id)" = "$EXPECTED_HOST_BOOT"
test "$(readlink -e /run/current-system)" = "$EXPECTED_HOST_CURRENT"
test "$(readlink -e /nix/var/nix/profiles/system)" = "$EXPECTED_HOST_PROFILE"
unit=install-microvm-cp-1.service
test "$(systemctl show "$unit" -p NeedDaemonReload --value)" = no
test "$(systemctl show "$unit" -p DropInPaths --value)" = ''
fragment=$(systemctl show "$unit" -p FragmentPath --value)
test "$(readlink -e "$fragment")" = "$EXPECTED_INSTALLER_UNIT"
printf '%s  %s\n' "$EXPECTED_INSTALLER_SHA256" "$EXPECTED_INSTALLER_SCRIPT" | sha256sum -c --status
test "$(readlink -e /fast/microvms/cp-1/current)" = "$EXPECTED_RUNNER"
test "$(readlink -e /fast/microvms/cp-1/toplevel)" = "$EXPECTED_GUEST_TOPLEVEL"
test "$(readlink -e "$EXPECTED_RUNNER/share/microvm/system")" = "$EXPECTED_GUEST_TOPLEVEL"
test "$(readlink -e /fast/microvms/cp-1/booted)" = "$EXPECTED_BOOTED_RUNNER"
```

The empty DropInPaths expectation is provisional until the built installer unit
is inspected. If it legitimately has source-owned drop-ins, compare their exact
immutable paths and contents; do not silently omit override validation. The
persistent activatable wrapper must be proven to reference the same expected
host closure/installer through its actual generated activation script. Merely
matching an arbitrary wrapper path does not establish that relationship.

Also require all sibling current/booted links and VM MainPID/start timestamps
unchanged from the pre-deployment receipt. Through the existing verified guest
route, recheck cp-1 boot ID, old running guest closure and all recovery units
stopped/PID zero; that is separate from selected next-boot runner identity.
Refresh survivor quorum/hash/backup gates and the private helper manifest only
after this host gate passes. Preserve booted old runner as evidence. There is no
post-health manual current pin in this revised ordering. Any mismatch closes the
removal gate; do not repair it by remote unit edits, forced symlinks or old WAL
restart. Source review and no-reboot observations do not prove an actual reboot. The
isolated fixture covers only its translated systemd ordering; actual reboot
behavior remains unobserved.

## Owner details still required before live execution

Verify the loaded installer ExecStart executable and complete argv against the
reviewed built unit/script. FragmentPath, NeedDaemonReload and script hash are
necessary but not the complete command check. `systemctl show ExecStart` embeds
runtime timestamps/PIDs; compare only its immutable executable/argv fields with
a strict parser or the owner's existing structured interface. Do not derive the
expected command from the live command being checked. The exact built unit is
pending, so no speculative parsing command is supplied here.

Independently verify the configured bootloader's actual default generation and
its selected host closure resolve to the durable containment candidate. A new
`/nix/var/nix/profiles/system` pointer alone is not proof that the next boot will
select it. Desktop owns the bootloader-specific read-only recipe and will bind
its evidence to the same source/host receipt; no generic bootloader guess or
reboot is authorized by this check.

Desktop source identifies systemd-boot with boot counting enabled (three tries)
and two retained configurations in `modules/hardware/systemd-boot-counting.nix`.
The owner must use read-only `bootctl list`/`bootctl status`, the actual ESP
`loader.conf`, and the selected entry's init path to verify the candidate default,
any one-shot override, and automatic fallback. A counter-bearing candidate entry
that can fall back to the old unsafe installer does not close the removal gate.
The claim that live switch normally writes a counter-free current entry requires
actual entry evidence; it is not assumed from source alone. No direct bootloader mutation or reboot is authorized by this check.

## Pinned source findings — 2026-11-22

The store paths in the source record below identify locally inspected immutable
source caches, not commands that depend on their presence on another machine.
Source provenance is baseline `030d17cf`'s **root** input mapping:
`root.inputs.nixpkgs = nixpkgs_4`, revision
`5c3cda7610193a82ba555e178e80de6667ae03de`, evaluated source
`/nix/store/pk5nyila4n9zn72dk6ilfpv99y3gqs2s-source`. The unrelated lock node named
`nixpkgs` is not the host root input. Deploy-rs root input is
`1cec0527bd09074bbee6d4461900ce5d58267217`, source
`/nix/store/v3yzs42ycmx17dfl5qzn00x6wxw4xrgz-source`. Systemd 262 source selected
by that same root package set was fetched without local compilation at
`/nix/store/hgvj3r5rf0hxx242vx92z8p6a0bzr3zf-source`.

### Boot default and automatic fallback

In root nixpkgs `nixos/modules/system/boot/loader/systemd-boot/systemd-boot-builder.py`:

- `BootFile.from_entry`, lines 201–219, hashes entry contents and reuses an
  existing matching-content entry filename, including any counter. Otherwise it
  creates `nixos-HASH+TRIES.conf` when boot counting is enabled, or a counter-free
  filename when disabled. A source comment that live switch always removes a
  counter is not an acceptance fact.
- `write_loader_conf`, lines 297–315, emits `preferred EXACT_ID` plus
  `default nixos-*` when counting is enabled. Exhausted preferred entries can
  fall through to another generation. With counting disabled it emits only
  `default EXACT_ID` (provided the intended configuration matched a generation).
  A missing match instead emits the wildcard and must fail this recovery gate.
- Lines 404 and 559–583 bind the entry's `init=` to the bootspec init path and
  select the default by comparing its parent with the requested configuration.
  Generation number or title alone is insufficient identity evidence.

Systemd `src/boot/boot.c` lines 1885–1950 select sysfail override, then one-shot,
then preferred EFI/config matches with assessment, then default EFI/config
matches without assessment. Lines 1655–1661 read OneShot/Default/Preferred EFI
variables; OneShot is consumed at boot. Lines 1272–1298 parse/decrement counters;
1790 puts exhausted entries last. Thus a counter-free candidate with an exact
loader.conf default still needs unsafe EFI/default/preferred/oneshot/sysfail
selection excluded. A manually selectable old entry remains unsafe after
quarantine; disabling automatic fallback is not permission to select it.

The supplemental host source sets `bootCounting.enable = mkForce false`.
Its evaluated assertion passed; completed build, exact host delta review and
live evidence remain separate gates.
Do not assume it strips an existing same-content counter: inspect the generated
entry and actual ESP filename. Existing unsafe entries can remain manual choices,
but no automatic preferred/wildcard/EFI override may select one during recovery.
No ad hoc `bootctl set-*`, blessing, entry deletion or firmware writes are part
of this check.

Read-only evidence commands supported by this pinned source are
`bootctl list --json=short` and `bootctl status --no-pager`, using the reviewed
candidate's systemd executable and configured ESP/XBOOTLDR paths. The JSON
renderer (`src/shared/bootspec.c:2313–2317`) provides `triesLeft`, `triesDone`,
`isDefault` and `isSelected`; absence of a counter field is distinct from zero.
The selected/current entry is not necessarily the next default. Preserve the
actual loader.conf and matched entry's filename/options, and cross-check EFI
selection reported by status. This is a source-grounded check specification, not an
observed live bootloader result.

### Deploy-rs confirmation and completion

There is no invented rollback timer to query. In the pinned deploy-rs source:

- `src/bin/activate.rs:363–390` installs a watcher and creates a canary after
  activation. `danger_zone` at 278–286 waits for deletion within confirmTimeout;
  `activate` at 755–762 calls rollback if confirmation fails.
- `src/deploy.rs:296–359` confirms through a separate SSH command deleting that
  exact canary. This is performed by the owner client, never manually by this
  gate. `src/lib.rs:18–26` derives canary/cancel names from the activation closure
  store hash and the configured temporary directory; do not infer from the guest
  toplevel or invent unit names.
- `src/deploy.rs:640–734` waits for the activation SSH child, confirms, then awaits
  activation completion and joins its task before returning. The rollback wait
  lives in that remote activation process; successful owner command completion
  plus terminated remote activation process closes that transaction's window.
  Seeing only “Activation succeeded!” or “Deployment confirmed.” is insufficient.

Require the exact owner `just deploy-rs kepler-cp1-recovery` process to
finish successfully, preserve its complete result, and verify the new running
and persistent host identities afterward. Bind the remote activation closure and
its command/process completion to the same receipt; if transport is lost or
completion uncertain, keep removal blocked. Do not manually remove canary files
or disable rollback. The baseline Kepler node uses magicRollback=true with
activationTimeout=300 and confirmTimeout=60; the supplemental node must export
its actual settings rather than silently inherit these numbers in the receipt.
This completion evidence proves no pending rollback from that completed process,
not cluster health, future absence of a new deployment, or actual reboot safety.
