# Orion/Apollo builders and guest-only KACE

**Status:** Guest-only KACE source verified; waiting for scheduled Orion cache build.
**Stage:** October 16 correction GREEN and independent review reconciled.

## Outcome and why

The latest [human seed](behavior.md) clarifies that the Ubuntu work VM is the
only machine that must keep KACE. Keep its apt-owned `ampagent` package and
`konea.service` checks, alongside WARP and Trend; do not reintroduce KACE on the
NixOS host. This supersedes earlier guest-removal instructions, not the selected
Orion/Apollo builder policy. Merge the correction and wait for Orion's next
scheduled cache build: no manual cache trigger, host build or activation.

The earlier uninstall attempt never reached the guest: SSH exited 255 with
`192.168.122.74 port 22: No route to host`. No apt command ran, so this correction
needs no runtime restoration, additional guest validation, backup or VM start.
Guest uninstall is cancelled, not pending work.

## Source changes and boundaries

Builder [PR #380](https://github.com/ErikBPF/desktop-nixos/pull/380) merged as
`22ba5efe2b458c8c2cbb88d365421ca13ea51811`. Orion/Apollo remain the remote pool,
with symmetric target exclusion, propagated Just overrides and bounded local
fallback. Kepler/Discovery have distinct encrypted source credentials for native
restricted, untrusted Nix RPC. No personal private keys were distributed. Orion
remains the official signed cache; existing automation is unchanged.

The guest boundary correction restores deployment health requirements, deletes
the now-inappropriate KACE uninstall helper/recipe, and updates the guide and
[documentary scenarios](behavior.feature). Source tests require guest checks and
prohibit removal entry points. The host module remains retired; that pre-existing
absence is GREEN, not a new RED anchor. The VM, its other agents, credentials and
data remain untouched.

Guest KACE is apt-owned, not a Nix fixed-output dependency. Keeping it does not
justify restoring obsolete Endeavour-only build batches or proprietary host
build exceptions. The [delivery plan](implementation-plan.md) records this
supersession explicitly; earlier seeds and failed-attempt receipts remain history.

## Evidence and review

PR #380 passed 73 pytest cases, nine update-safe unittest cases, five-host dry
gates and all eleven CI checks. Independent source/security/operations/simplicity
and editorial findings were reconciled. Native Alejandra/ripsecrets/Statix hooks
passed. Those receipts establish the earlier builder source, not runtime rollout
or the new correction's final test result.

Correction RED observed two failures for missing guest requirements and an unwanted
uninstall entry point; focused GREEN passed 19 tests. After rebasing onto current
main `cebf11d0`, integrated verification passed 74 pytest and nine unittest cases,
plus lint, formatting, docs links, shell syntax and whitespace checks. Independent
security/correctness/editorial/simplicity review found no blocker; its missing
unsigned-input caveat was restored in the delivery plan. The rebase preserves
upstream Hermes index rows and its Orion-only validation regression.

NixOS modules, encrypted credentials and cache configuration match current main;
no host closure is built or activated by this follow-up. Garbage-collected hook
tooling was restored through the declared dev shell, not bypassed. CI remains the
publication gate; its result belongs to the correction PR, not the older #380 run.

## Waiting work and recovery

Publish reviewed source through a follow-up PR, then wait for scheduled Orion
cache publication. Do not retry guest removal or manually deploy. Future host
rollout still requires existing closure/unit-diff/rollback gates, restricted-RPC
and secret-installation evidence, and Kepler's supervised stability window.
Native fallback can include busy/ineligible remote capacity; `preferLocalBuild`
and unsigned-input limits remain documented in the delivery plan. Revert only
task-owned source through normal review; preserve older worktrees, unrelated
keys/data and immutable history. Stop after three repairs of the same failure.
