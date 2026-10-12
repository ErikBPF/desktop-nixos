# Orion main-ready recovery verification

**Status:** Initial and restored-schedule RED/GREEN verified; publication and runtime rollout pending.

## Scope and provenance

Preserve the [human seed](behavior.md) and the earlier accepted recovery policy
without copying its stale lock file or live-build authorization. The subsequent
human request supersedes timer pause: restore 03:00 with persistence and allow
immediate catch-up. Publication, merge and Orion update are now authorized,
subject to checks and preview. The [behavior examples](cache-and-update.feature)
are unautomated Gherkin, not a claim of executed scenarios. The old task's
accepted contract includes seven sysctls; read-only runtime inspection confirms
`kernel.watchdog=1` and `kernel.watchdog_thresh=30` alongside the five previously
reported values. Retaining these is preservation, not a new watchdog policy.

Implementation belongs only in `modules/hosts/orion/default.nix`. Shared cache,
power, sleep, telemetry, and WOL modules remain unchanged. Remove only the
temporary cache-timer disable override; retain recovery and builder bounds.
Restored automatic cache work is authorized; panic induction, firmware changes,
filesystem repair and unrelated stress tests are not.

## Smallest runnable seam

The existing four-test stdlib runner is adapted at
`tests/orion-main-guardrails/test_options.py`; its original checkout remains
untouched. Evaluate fully merged `nixosConfigurations.orion.config` with
`nix eval --json --apply`; do not use source greps as the behavioral oracle.
Disable IFD and distributed builders and use only explicit public substituters.

Assertions:

- Panic timeout 10, panic on Oops/soft/hard lockup enabled, both CPU watchdogs
  enabled, watchdog threshold 30; retain the existing `panic=10` boot parameter
  without conflicting panic parameters.
- Existing WOL oneshot still arms `enp4s0` with magic packets.
- Existing cache-builder oneshot stays enabled with `CPUQuota="400%"`,
  `TimeoutStartSec="89min"`, `TimeoutStopSec="1min"`,
  `KillMode="control-group"`, and `SendSIGKILL=true`. `NIX_CONFIG` retains two
  jobs and a two-core build hint, without conflicting duplicate assignments.
- Both existing cache timer and generated timer unit have `enable=true`;
  absence does not count as restoration. Require `wantedBy` to include
  `timers.target`, `OnCalendar="03:00"` and `Persistent=true`. Do not
  suppress/remove the generated unit.
- Existing sleep/suspend/hibernate/hybrid-sleep targets remain disabled and
  logind idle/suspend/hibernate/lid actions remain ignored.
- Selected non-recovery configuration matches immutable main
  `f2d020432580f8ca30d23f917c4053e2e20054d5`: kernel package/parameters,
  shared cache-build script and cache-serving configuration, WOL unit,
  sleep/logind policy, and automatic-upgrade behavior. Baseline must evaluate
  independently; a failed baseline is never replaced by the candidate.

Keep `flake.lock` unchanged, checked by Git diff. This preserves latest-main
developer tooling without inventing a second package/version authority.

## RED → GREEN and owner gates

Run from this checkout with local probe settings:

```sh
export NIX_CONFIG='builders =
max-jobs = 0
allow-import-from-derivation = false
substituters = https://cache.nixos.org https://nix-community.cachix.org https://hyprland.cachix.org
extra-substituters ='
python3 -B tests/orion-main-guardrails/test_options.py
```

The first revision's RED required successful evaluation followed by assertion
failures for missing recovery settings/builder bounds and enabled timer on
unmodified main. Preserve those receipts. The restored-schedule revision's RED
must now fail because the candidate still pauses the timer; its existing
recovery/builder/preservation tests should pass. An evaluation, network, cache,
or syntax error is not RED. Record the new RED before removing the override.

GREEN runs the same unchanged test expectations after the minimal host patch.
Print `ORION_MAIN_GUARDRAILS_OK` only after the nonempty suite passes; failure
exits nonzero without that marker. Then run `just lint`, `just fmt-check`,
`just docs-check`, and the owner-approved targeted alternative:

```sh
nix build .#nixosConfigurations.orion.config.system.build.toplevel \
  --dry-run --no-link --no-write-lock-file \
  --builders '' --max-jobs 0 \
  --option allow-import-from-derivation false \
  --option substituters \
    'https://cache.nixos.org https://nix-community.cachix.org https://hyprland.cachix.org' \
  --option extra-substituters ''
```

Initial paused-schedule evidence: four tests, 16 assertion failures, exit 1, no evaluation errors;
preservation passed against the independent baseline. Observed GREEN: the same
four tests pass with the success marker. Review added the already-required
timer-suppression check; augmented GREEN passed and a controlled suppressed
timer input was rejected. These receipts do not claim a live recovery test.

Restoration evidence: four tests, two assertion failures for the disabled
configured/generated timer, exit 1, no evaluation errors; the other three
tests passed. After removing the override, all four tests passed with
`ORION_MAIN_GUARDRAILS_OK`. `just dry orion`, lint, fmt-check and docs-check
passed. October 12 investigation receipts preserve `restore-red.txt` and
`restore-dry.txt`; no unautomated Gherkin scenario is claimed executed.

Do not run local `nix flake check`, `just eval`, `just check` or `just dry-all`.
After renewed GREEN, owner real-build/preview/deployment recipes are authorized
for Orion; unlike the earlier source-only stage, they can transfer closures and
activate the host. Use the verified Kepler builder and inspect exact closure,
kernel/modules and timer-trigger effects before activation. CI remains the
full-flake gate. The idle observation has completed.

## Limits and rollout

CPU quota is aggregate CPU time, not four pinned cores; core count is a hint.
Nix-daemon builds may escape the service cgroup, and uninterruptible tasks can
defeat timely cancellation. Static assertions do not prove containment, crash
recovery, filesystem safety, or long-term stability. Ten-second delay starts
after panic, not after the initial hang. No additional sleep-backend toggles,
kernel/THP/GPU changes, upgrade-policy change, or new WOL mechanism is included.

Deploy only the reviewed merged source using owner preview/deploy/verify
recipes and exact closure review. Record running, booted and profile targets;
stop on an unexplained mismatch. User-approved persistent catch-up can launch
the bounded cache warmer immediately, independently of activation restarts.
Observe fresh SSH/boot identity and affected services. Cancel runaway/new-fault
cache work only through `just stop-recache-orion`; do not manually reset timer
state or remove earlier user work. Preserve private OpenCode backup and previous
system generation; no forced reboot or blind rollback is authorized.
