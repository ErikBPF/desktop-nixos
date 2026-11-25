# Kindle automatic ejection

**Status:** PR ready; local checks and Endeavour dry build passed.

## Outcome and scope

Human seed, preserved verbatim:

> lets create a script for auto-disconecting kindle when it is connected to this pc

Endeavour checks every five seconds during the user session and safely ejects
the connected Kindle's storage. Matching requires USB transport and serial
`90D42201420401EB`; other disks are ignored. Each mounted filesystem is
unmounted through UDisks before the drive receives its eject command. A failed
unmount stops the operation. No forced unmount or USB power-off is used.

The [Home Manager module](../../../modules/desktop/kindle-auto-eject.nix)
installs `~/.local/bin/kindle-auto-eject` with pinned Python, lsblk, UDisks and
busctl dependencies, and owns the user service and timer. Only Endeavour imports
the module. The [script](../../../modules/desktop/_kindle-auto-eject.py) retains
the behavior already exercised against the connected device. No system rebuild
or deployment is part of creating this PR.

## Evidence and limits

The original local implementation was exercised on 2026-11-25. UDisks first
refused ejection because `/dev/sda1` remained mounted. Investigation showed
that lsblk JSON is flat when requesting `PATH` without `NAME`, unless `--tree`
is explicit. A regression assertion failed before adding `--tree`; after the
repair the service unmounted `/dev/sda1`, logged `Kindle storage safely
ejected.`, and exited successfully. lsblk then showed the Kindle at `0B`
without a mounted partition. Subsequent timer runs succeeded without repeated
ejection. This is observed storage ejection, not confirmation of the Kindle's
screen state or charging indicator.

The [six tests](../../../tests/kindle-auto-eject/test_kindle_auto_eject.py)
cover mounted and unmounted media, device-name changes, absent or unrelated
devices, already-ejected media, explicit tree output, and stopping on a busy
filesystem. They isolate OS commands and do not manipulate actual disks.
For repository packaging, the six assertions first failed because the script
was absent. The workflow runs them on pull requests.

Repository validation passed: all six tests, `just lint`, `just fmt-check`,
`just docs-check`, and
`nix build .#nixosConfigurations.endeavour.config.system.build.toplevel --dry-run`.
Targeted Nix evaluation also confirmed the pinned service executable and
five-second timer. `just structure-check` reports an existing false duplicate:
its grep counts the `kepler-development` reference in `recovery.nix` alongside
the registration in `development.nix`; both lines already exist on the base
commit. This unrelated checker issue was left unchanged. Canonical Graphify
AST update completed without topology changes; no worktree graph was created.

Physical unplug/replug and charging remain unverified. UDisks authorization
depends on the active desktop session; an inactive session may deny ejection.
The timer retries failed operations without forcing them. The serial and
UDisks object path are intentionally specific to the existing Kindle.

## Operation and recovery

Run the script manually with `~/.local/bin/kindle-auto-eject`. Pause before
transferring books, then reconnect the Kindle:

```sh
systemctl --user stop kindle-auto-eject.timer
```

Resume automatic checks:

```sh
systemctl --user start kindle-auto-eject.timer
```

Read logs with `journalctl --user -u kindle-auto-eject.service -n 20 --no-pager`.
The previously installed local files stay active until a normal Home Manager
activation; its configured `.backup` policy handles the existing unmanaged
script and unit files. Before activation, ensure no stale `.backup` files
conflict. Rollback is to stop the timer and revert the Endeavour import.
