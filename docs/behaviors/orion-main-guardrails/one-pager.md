# Orion main-ready recovery controls

**Status:** Restored-schedule source passes focused tests; publication and update pending.

## Outcome and why

The source candidate preserves Orion's deployed recovery controls on latest
main. A single host-module patch restores controls that an unchanged main
deployment would discard. This is containment and recovery configuration, not
a demonstrated fix for kernel-memory corruption or Steam-related loss of
contact. The [human seed](behavior.md) remains verbatim.

Subsequent approval restores the 03:00 cache schedule with persistent catch-up,
permits immediate overdue work, and authorizes publication/merge plus Orion's
OpenCode v2 update. The timer-pause requirement is superseded explicitly, not
silently removed for a passing test. New RED/GREEN and rollout evidence follow
the [revised contract](test-contract.md).

Freshly fetched main is `f2d020432580f8ca30d23f917c4053e2e20054d5`. Its Orion
toplevel differs from the observed booted system despite both using kernel
7.2.7. Main disables the NMI watchdog, omits panic-on-Oops/lockup settings, and
enables the nightly cache builder without deployed resource/time bounds.

## Initial paused-schedule evidence and limits

The [test contract](test-contract.md) evaluates the fully merged configuration
and compares preservation controls against immutable main. RED ran before
production edits: four tests produced 16 assertion failures, exit 1; the
preservation test passed. The module's RED hash matched main. GREEN passed
the same four tests with `ORION_MAIN_GUARDRAILS_OK`.

Independent conformance review found one missing timer-suppression assertion;
it was added without changing production code or acceptance. The augmented
four-test suite passed, and a controlled suppressed-timer input was rejected
with `ORION_SUPPRESSED_TIMER_REJECTED`. First-draft RED/GREEN receipts remain
preserved; the additional check does not rewrite their history.

`just lint`, `just fmt-check`, `just docs-check`, and the owner-approved Orion
toplevel `--dry-run` passed. Builders and IFD were disabled and only public
substituters were used. No actual build, closure transfer, activation or host
configuration change occurred. This proves evaluated settings and dependency
planning, not compilation, runtime containment, crash recovery or stability.
Full-flake checks remain CI-only.

## Changes and preserved boundaries

The initial 26-line recovery patch was transplanted into
`modules/hosts/orion/default.nix`: seven accepted sysctls, initially masked cache timer,
two-job/two-core build hints, `CPUQuota="400%"`, 89-minute start and one-minute
stop limits, and service-cgroup cleanup. The ten-second reboot delay begins
after panic, not after the initial freeze. The quota limits aggregate CPU time,
not four pinned cores; Nix-daemon work may escape the service cgroup.

The stdlib runner reuses the earlier recovery seam. Latest-main inputs and
developer tooling remain intact; `flake.lock` is unchanged. Kernel, THP, GPU,
firmware, WOL, sleep controls, cache-serving/build script and automatic-upgrade
policy were not changed. Existing dirty `worktrees/orion-recovery-wol` remains
untouched. Candidate branch: `fix/orion-main-guardrails-20261012`, checkout
`worktrees/orion-main-guardrails-20261012`.

## Review, risks and recovery

Independent seed/conformance, security, reliability, performance, architecture,
test, compatibility and operations reviews found no production defect or
blocking source finding. Structure/prose review replaced stale planning text
with observed outcomes. The accepted seven-setting policy was retained rather
than silently narrowed to the abbreviated initial comparison.

Panic recovery can lose unsaved work; hard hangs and uninterruptible tasks can
defeat cancellation. Memory-corruption cause and filesystem damage remain
unresolved. Source rejection affects only task-owned changes; no host rollback
is needed. No commit, publishing, merge, deployment, reboot or stress test was
performed.

## Continuing work

After the human set Steam's native AC idle sleep to Never, the independent
11:56–13:46 −03 observation completed: 110/110 SSH checks succeeded, zero boot
changes, final sampled uptime 9,996.4 seconds. ICMP failed throughout, including
baseline while SSH worked, so ping is not an outage signal here. This passed
the stated reachability metric beyond the reported 80–90-minute cutoff.

Post-check found no selected suspend/fault markers; Steam logs stopped before
the interval and kernel produced no interval entries, so those absences do not
prove complete event capture. Minute SSH probes add activity. One successful
window supports the Steam-idle hypothesis, not fault clearance or long-term
stability. Earlier panic/checksum evidence remains unresolved.

Read-only recheck at 17:17 −03: SSH reachable, same boot ID, uptime 6h18m;
runtime recovery settings and masked timer/sleep targets still match policy.
No selected new kernel fault/suspend entries were captured since 13:46. Fresh
fetch confirms main remains `f2d0204`; source candidate is still unpublished and
unactivated. This later point check does not extend the bounded campaign.

Publication, merge and update are now approved; checks, private OpenCode state
backup, real build, exact preview and fresh runtime verification remain gates.
Kepler builder preflight succeeded. Audit found no telemetry mitigation proven
safe to remove: retain GPU-hwmon/NFS exclusions, journal retention, sleep/WOL,
routing and recovery controls. LACT clock ownership and boot-only upgrade
health rollback remain separately identified investigations, not speculative
removal. No human-authored lessons are invented.

### Revised delivery slice

Outcome: enabled persistent 03:00 timer with existing builder/recovery limits.
One slice owns the host override and merged-option unittest. RED: run
`python3 -B tests/orion-main-guardrails/test_options.py` with restored-schedule
assertions against still-paused source; require assertion failures, not eval
errors. GREEN: remove only the host timer-disable block and rerun all four
tests; require exit zero and `ORION_MAIN_GUARDRAILS_OK`. Then lint, formatting,
docs links and `just dry orion`; independent review precedes publication.
Required CI must pass before merge. Build merged Orion with `just build orion`,
inspect `just deploy-rs-preview orion`, then `just switch-orion` and fresh
runtime verification. Record exact source and closure identities throughout.
Catch-up now is explicit approval, not a harmless activation side effect;
new faults or health failure stop rollout. Existing owner cache-stop recipe
is the bounded-load escape; no unrelated tuning or blind rollback is added.

Restoration RED produced two assertion failures (configured/generated timer
disabled), with three other tests passing and no eval errors. Removing only
the three-line disable block yielded four passing tests and
`ORION_MAIN_GUARDRAILS_OK`. Production diff is now 23 added lines versus main;
the schedule inherits shared 03:00/persistent defaults. Lint, fmt-check and
docs-check passed. Receipts remain under the October 12 investigation's
`orion-main-guardrails/restore-red.txt`; initial RED is not rewritten.

### Authorized private OpenCode backup entry point

Before deployment, use LAN SSH `ssh -p 2222 -i ~/.ssh/id_ed25519
erik@192.168.10.220 'bash -s'` and send the block below on stdin, not as the
remote command string (the writer check would match that string). Orion preflight observed no
OpenCode process/service, current HM v1 package, no imperative shadow, and
adequate free space. Recheck no writers; prevent launches during backup and
update. If active writers appear, stop rather than copying live SQLite files.
Archive includes DB/WAL/SHM and unmanaged config without dereferencing managed
Nix-store links. Treat archive as secret; never upload it or expose contents.

```sh
set -eu
if pgrep -u "$(id -u)" -f '[o]pencode' >/dev/null; then
  echo 'OpenCode process present; stop backup and quiesce first.' >&2
  exit 1
fi
umask 077
backup=$(mktemp -d "$HOME/.local/share/opencode-backup-orion-pre-v2-20261012.XXXXXX")
chmod 0700 "$backup"
readlink -f "$HOME/.local/state/home-manager/gcroots/current-home" > "$backup/home-generation.txt"
tar -C "$HOME" -cpf "$backup/state.tar" \
  .config/opencode .local/share/opencode .local/state/opencode
chmod 0600 "$backup/state.tar"
tar -tf "$backup/state.tar" >/dev/null
sha256sum "$backup/state.tar" > "$backup/state.tar.sha256"
printf 'OPENCODE_PRIVATE_BACKUP_OK %s\n' "$backup"
```

Retain backup and rollback generations; managed config links still depend on
old Nix-store targets, so do not garbage-collect them during migration. Archive
validation proves readability, not a restoration drill or complete DB integrity.
Do not restore over active state or hand-edit HM config. Post-deploy binary
version checks are allowed; first interactive v2 use is a separate migration
observation, not implied by installation. Built-in v2 TUI replaces v1-only
`opencode-tui` API clients.

Fresh independent review found no blocking production defect; corrected stale
paused-schedule wording/status and documented stdin backup invocation. The
restored candidate passed `just dry orion`. Private OpenCode archive completed
with `OPENCODE_PRIVATE_BACKUP_OK` at the documented 0700 backup directory;
receipt stores path, not archive contents. Current/booted system and profile's
underlying system agree, kernel/module/initrd identities are recorded. Existing
`nixos-upgrade.service` is failed before rollout; no selected new fault markers
were captured at 18:25, but journal's empty match returns exit 1 and is not
itself a service-health failure. A pre-merge candidate build is in progress;
merged source still requires exact build/preview identity verification.
