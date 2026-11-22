# OpenCode coding authority parity with Pi

**Status:** Implemented and independently reviewed; preparing merge after a later system activation restored the old policy.

## Seed and accepted behavior

“lets change opencode to be able to rede tokens ans secrets”

“lets run at the same level of permissions that a pi harness runs”

Pi's implementation in the `pi-durable-20261122` worktree registers
`createCodingTools` without a permission hook or sandbox. Its README states that
read, write, edit and bash use the invoking user's filesystem/network authority.
The code-mode QuickJS memory sandbox does not restrict those tools. This change
matches that coding authority in OpenCode, rather than adding an approval gate.

## Changes and boundaries

Remove global protected reads, hard tool-use denials, secret-edit restrictions,
lockfile prompts and shell command denials. Remove their duplicates in workspace
roles and the backend-state file restrictions. Both workspace profiles inherit
the global rules. The direct-launch repository config permits read, edit, bash
and external directories. Keep provider routing, native subagents and the
three-level dispatch boundaries unchanged. OS permissions, service identities,
file ownership and credentials do not change. No real secret is read for testing.

## Evidence

Updated permission assertions failed against the old settings (37 failures,
including secret reads and lockfile edits). After implementation, six evaluated
settings tests and three project-config tests pass. Full profile/runtime checks,
lint, formatting, affected host evaluation and independent review follow.
Tests use synthetic path strings, not actual secrets or destructive commands.

## Risk and recovery

Tools may read secrets into model context and session history and can execute
any command the user account permits. Repository instructions still apply but
are not a sandbox. Restoring the removed rules restores the prior harness policy;
it cannot remove values already sent to a provider or persisted in a session.
Activation must preserve unrelated Home Manager work and verify effective settings.


## Final validation and activation

All 18 OpenCode profile/runtime tests, 37 workspace tests and three project
configuration tests passed. The isolated V2 server returned allow for synthetic
secret paths without reading their contents. Independent review found no blockers
and separately passed the project/profile checks. Lint initially requested
`inherit (base) permissions`; that equivalent simplification was applied, then
lint, formatting and docs checks passed. Endeavour's toplevel dry build passed.
Canonical Graphify AST update completed; no worktree graph was created.

Home Manager build and dry activation passed. Comparison found the active user
generation had reverted to the older plain-SSH launcher; activation restores the
already approved workspace picker along with current merged instructions. No
voice bindings or other unmerged configuration were removed. The owner command
`just home-switch endeavour` exited zero and activated generation
`/nix/store/k82plx3ja37vldvc2pwanl2g6xbgpyx3-home-manager-generation`.
Both OpenCode services restarted and are active. Installed global settings and
each service's immutable wrapper profile were checked: read/edit/shell allow
all paths, no tool-use denials, provider policies and dispatch boundaries retained.
Hyprland reports no configuration errors. No system switch or remote host deploy
was performed. This local activation can be superseded by a later deployment
until the source change is committed and merged.

Receipts: `/tmp/opencode-pi-red.log`, `/tmp/opencode-pi-profiles.log`,
`/tmp/opencode-pi-workspace.log`, `/tmp/opencode-pi-dry.log`,
`/tmp/opencode-pi-preview.log` and `/tmp/opencode-pi-activate.log`.


## Merge preparation

The initial local activation was verified, but a later system activation replaced
its configuration with the old policy. A fresh live check found 11 secret-read
policy denials in both running backend profiles. The user requested merging this
change into main so future deployments retain it. Preserve the earlier activation
receipt as historical evidence, not current-state proof. Refresh against main,
rerun checks and require CI plus exact-head review before merging. This merge
step does not itself reactivate the host.


CR reconciliation: the session guide still named the deleted deny tail, and the
older shell-permissions proposal remained active. Updated the guide to describe
OS authority and moved the superseded proposal to `docs/implemented/`, retaining
its seed and S1/S2 history with links to current policy. No behavior changed.
All 58 focused tests passed after the main rebase; the later main update only
changed tuicr test wiring. Fresh CI and review cover the final published head.
