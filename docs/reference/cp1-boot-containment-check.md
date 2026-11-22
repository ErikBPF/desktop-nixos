# cp-1 pre-removal boot containment check

**Status:** Host build passed; held for exact-head review and fresh live
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
Capture the exact expected host closure, installer unit target and installer
script SHA256 from the built artifacts. The expected running and persistent
system profile is the same `492mc5…` host path recorded in the
[sequence](cp1-durable-recovery.md). Do not infer expected values from the live
host under test.

Require the existing owner `just deploy kepler-cp1-recovery 192.168.10.230`
command to complete successfully, then independently verify authenticated SSH
reachability and every profile/installer/bootloader check below. This
`nixos-rebuild switch` route has no automatic deploy-rs rollback. A command error,
lost transport or partial activation leaves member removal blocked; no automatic
old-profile rollback or manual bootloader repair is authorized by this check.

The actual built `492mc5…` unit resolves to
`/nix/store/cbcrfqfijcbq41lw2ihwhmpgr5hxh5kw-unit-install-microvm-cp-1.service/install-microvm-cp-1.service`.
Its sole ExecStart executable is
`/nix/store/h7z0f18p6q6riizjdy9jjz3viyrs1a07-unit-script-install-microvm-cp-1-start/bin/install-microvm-cp-1-start`,
with no arguments and WorkingDirectory `/fast/microvms/cp-1`. The script SHA-256
is `8b793b91ae778148be74743940596b29a3533f1c00a71f22bce0d9666163eb48`.
These are inspected build artifacts, not observed loaded runtime state. Match
the loaded executable and complete argv to these values before removal.

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
busctl=/nix/store/kh0kk4mi6hr0cdvsc8rzd0jvr2c2vhwk-systemd-262/bin/busctl
object=$(timeout 10 "$busctl" --system --json=short call \
  org.freedesktop.systemd1 /org/freedesktop/systemd1 \
  org.freedesktop.systemd1.Manager GetUnit s "$unit" | \
  jq -er 'select(.type == "o" and (.data | length) == 1) | .data[0] |
    select(type == "string" and startswith("/org/freedesktop/systemd1/unit/"))')
timeout 10 "$busctl" --system --json=short get-property \
  org.freedesktop.systemd1 "$object" org.freedesktop.systemd1.Service ExecStart | \
  jq -e --arg script "$EXPECTED_INSTALLER_SCRIPT" '
    .type == "a(sasbttttuii)" and (.data | type == "array") and
    (.data | length) == 1 and .data[0][0] == $script and
    .data[0][1] == [$script] and .data[0][2] == false' >/dev/null
printf '%s  %s\n' "$EXPECTED_INSTALLER_SHA256" "$EXPECTED_INSTALLER_SCRIPT" | sha256sum -c --status
test "$(readlink -e /fast/microvms/cp-1/current)" = "$EXPECTED_RUNNER"
test "$(readlink -e /fast/microvms/cp-1/toplevel)" = "$EXPECTED_GUEST_TOPLEVEL"
test "$(readlink -e "$EXPECTED_RUNNER/share/microvm/system")" = "$EXPECTED_GUEST_TOPLEVEL"
test "$(readlink -e /fast/microvms/cp-1/booted)" = "$EXPECTED_BOOTED_RUNNER"
```

The empty DropInPaths expectation is provisional until the built installer unit
is inspected. If it legitimately has source-owned drop-ins, compare their exact
immutable paths and contents; do not silently omit override validation. The
running and persistent host paths must both resolve to the reviewed host
toplevel; its actual generated installer must select the safe runner. The
withdrawn `aq1z3…` wrapper is not an acceptable persistent-profile target.

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

The structured assertion above reads the loaded unit through systemd's D-Bus
API using the candidate's pinned systemd 262 `busctl`. `GetUnit` returns one
object path; `ExecStart` has type `a(sasbttttuii)`. Require exactly one command,
the reviewed executable path, argv containing only that path, and
`ignore_errors=false`. Runtime timestamps, PID and exit-status fields do not
change the immutable command expectation. Empty or additional commands, altered
arguments or ignored failures reject the gate without printing their values.
The schema was calibrated read-only against a local service, not production;
Kepler's loaded command remains to be checked after approved deployment.

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
Its evaluated assertion and host build passed; exact-head review and live
evidence remain separate gates.
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

### Withdrawn wrapper and selected owner route

The built deploy-rs wrapper `aq1z3l8qmpzgwmgyczix15146ji43002` contains
`sed -i '/^default /d' /boot/loader/loader.conf` after the host switch. It would
remove the required exact default. It was never executed and is withdrawn;
the supplemental deploy node is removed. Earlier process-local canary/confirmation
research remains historical evidence, not the completion gate for this procedure.

Use only the reviewed owner `deploy-preview` and existing `deploy` recipes named
in the [sequence](cp1-durable-recovery.md), which preserve the standard remote
`nixos-rebuild` flags and select the host toplevel directly. No ad hoc replacement
deployment command, canary deletion, auto-rollback assumption or manual old-host
rollback is valid. Require owner command exit zero AND fresh reachability,
installed-command, selected-runner, host-profile and actual bootloader evidence
before opening the irreversible gate. No host or guest operation has occurred
as part of preparing these documents.
