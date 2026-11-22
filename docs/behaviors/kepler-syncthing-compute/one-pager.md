# Kepler Syncthing compute folders

**Status:** Syncthing configuration active on both hosts; initial Documents sync pending.

## Outcome and why

Keep independent local copies on Endeavour and Kepler, with Kepler's copies on
its SSD pool. Explicit pool paths were selected instead of home aliases.
The source of truth is `modules/services/syncthing-fleet.nix`.

## Delivery and verification

One slice: add Documents/Downloads sharing between Endeavour and Kepler, retain
all existing peers and exclusions, and guard pool folder creation and the daemon
with the mount dependency. Evaluate topology and service ordering in a regression
test, observe assertion failure before implementation, then run the ignore-policy
suite, lint, formatting, and both host dry builds. Review the final diff independently.
Deployment remains separate from source validation; live sync completion needs
both host configurations activated and Syncthing API verification.

## Evidence and limits

Live checks: Endeavour has idle Documents (28,472,432,840 bytes) and Downloads
(317,442,277 bytes); Kepler currently shares only tofu-state. `/fast` is mounted
from `fast-pool/data`, with 588,627,836,928 bytes available. Proposed destination
directories do not exist. Existing home folders will remain untouched.

## Decisions and recovery

The two answered async questions selected explicit pool paths and separate copies
on both hosts. Keep `.git`, `.env`, build/cache and state-file exclusions; this
is working-file synchronization, not a complete Git repository migration.
Rollback removes the new shares through configuration; retained files must not be
deleted. Mount failure will stop the whole Kepler daemon, including tofu-state,
until the pool is available again and Syncthing is restarted. Remounting alone
does not guarantee service restart. No destructive mount test on the live host.


## Implementation and review evidence

The initial regression run failed with three assertions: both Kepler folders
were absent and the mount prerequisite was missing. After implementation, all
three tests in `python3 -m unittest discover -s tests/syncthing-ignore -v` passed,
including the existing six-host ignore activation test. An intermediate Nix
evaluation failed because `escapeSystemdPath` belongs to NixOS `utils`, not `lib`;
that namespace was corrected, with no acceptance changes.

`just lint`, `just fmt-check`, `just docs-check`, and `nix build
.#nixosConfigurations.<host>.config.system.build.toplevel --dry-run` passed for
both Kepler and Endeavour. The dry builds evaluate/build-plan the system; they
do not prove live activation or data transfer. Existing CI discovers the new
tests through its existing Syncthing test command. The evaluated preparation
script passed `bash -n`; ShellCheck was unavailable on this workstation.

A fresh reviewer checked the settled plan and then the implementation and
evaluated service, finding no blocking issues. The final revision clarifies
manual restart after mount recovery. The implementation retains only topology,
mount dependencies and guarded folder preparation; no extra sync service or
migration machinery. New copies connect directly through Endeavour, so the
initial transfer requires Endeavour online.

## Continuing work

Publish/review the source change and verify Documents reaches complete initial
synchronization after its index exchange and transfer finish. Home Manager activation alone cannot apply these
system-service changes. Existing data has not been moved or deleted; both live Syncthing configurations
now include the reciprocal shares. Mount-loss handling was inspected in the
evaluated unit, not exercised destructively against Kepler's active pool.


## Activation receipt — 2026-11-21

User authorized activation with “do sync”. Both system closures built on Orion.
Kepler's kernel and module paths match its prior running system, and
`just deploy-rs-preview kepler kepler` passed before `just deploy-rs kepler kepler`
confirmed activation with magic rollback. Active system:
`/nix/store/zi7mrrickfv7haaglmy7yrsljr9zgk9p-nixos-system-kepler-26.11.20261115.5c3cda7`.

`just switch endeavour` installed
`/nix/store/xyyl2cbmhrk1q2rz4jl50lvmxrab2bc8-nixos-system-endeavour-26.11.20261115.5c3cda7`
and applied Syncthing successfully, but returned status 4 because Home Manager
refused to clobber the separately installed `~/.config/hypr/hyprland.lua` symlink
to `voice-hyprland.lua`. That user configuration was preserved; the Home Manager
failure remains unresolved. Both native OpenCode backends and desktop-tmux remain
active. All three credential paths flagged by the dry-activation output remain
readable after activation; no credential values were inspected or reported.

Live Kepler: both destinations are mode 0700, owned by erik, backed by
`fast-pool/data`. Syncthing is active with `BindsTo=fast.mount`, ordering after
that mount, and `RequiresMountsFor=/fast`. Both folders are sendreceive/unpaused,
with reciprocal sharing observed from both APIs. Downloads reached idle with
408 local/global files, 317,442,277 bytes, zero needed bytes and zero errors.
Documents is receiving its initial index (2,697 files advertised at last check,
not the full expected approximately 956,000); no errors were reported. Do not
interpret the partial remote index as completed synchronization.

Local transient build/preview/activation logs: `/tmp/compute-sync-build.log`,
`/tmp/compute-kepler-preview.log`, `/tmp/compute-kepler-activate.log`,
`/tmp/compute-endeavour-preview.log`, `/tmp/compute-endeavour-activate.log`.
Live status was read with `/tmp/compute-sync-status.sh`, which passes the API key
through curl stdin and reports only configuration paths and transfer counters.
