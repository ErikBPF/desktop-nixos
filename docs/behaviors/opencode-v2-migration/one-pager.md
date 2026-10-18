# OpenCode V2 backends: delivery status

**Status:** Earlier native/plugin repair verified; PR #375 merged externally and candidate built/reviewed; Q-16 accepts Hermes scope. GitGuardian false positive resolved by user uninstall. Branch synced through #383; refreshed candidate validation and activation pending.
**Stage / revision:** Post-merge source/status sync / 20, 2026-10-18.

## Outcome and why

Earlier plugin-repair receipts showed both Endeavour backends running native
V2 2.0.27 with RTK, gateway headers and
Ponytail active, zero failed plugins, authenticated native clients and correct
gateway defaults. Guarded user activation retired the obsolete HM-owned V1
RTK symlink into a mode-0600 backup outside plugin discovery. V1 metadata and
all 16 current tmux panes/PIDs remained unchanged. Two windows changed during
verification; Q-10 confirms user action. The failed window receipt remains,
not rewritten into a passing whole-desktop assertion.

Earlier boot invoked pre-V2 system HM while standalone HM installed V2,
explaining stale startup config despite correct current files. External system
activation since then installed native V2 system HM successfully. This task
performed user repair, not that system switch; reboot behavior remains untested.

Verbatim seed and accepted contracts remain in the
[owning leaf record](https://github.com/ErikBPF/opencode-flake/tree/5dca70f302d8b8ad5f52feea2c2bac347cd24858/docs/behaviors/opencode-v2-migration).
[Leaf #55](https://github.com/ErikBPF/opencode-flake/pull/55) merged and published
FlakeHub 0.1.54. [Desktop #373](https://github.com/ErikBPF/desktop-nixos/pull/373)
and status [#374](https://github.com/ErikBPF/desktop-nixos/pull/374) are now merged
externally. User selected RTK retirement, roaming-builder recovery and sudo-PATH
reconciliation for combined main delivery. Other dirty worktrees stay untouched.

## Changes and decisions

Q-1 selects native servers/clients, not V2-server/V1-Rust pairing. Q-2 keeps
Fold/sidebar disabled. Q-3/Q-4 permit verified Endeavour user activation and
publication. Q-5 permits V1 homelab chmod only, never history/schema migration.
Q-6 permits leaf publication/pin. Q-7 retains hash-pinned Ponytail adapter 0.1.0;
incompatible upstream 5.1.1 is deferred.

Backends isolate databases/data/state/cache and scoped credentials; prompted
original-command approval precedes RTK execution. Provider-filtered headers,
title/default routing, native secret-denial policies, disabled updater and
legacy-discovery suppression remain. Only Work DeepSeek's rejected effort
options were removed. Config and retirement-script restart triggers refresh
cached server inventory without restarting persistent desktop tmux.

Q-9 approves retirement only for an existing store-backed symlink matching the
verified V1 RTK hash. Unknown files, non-store links and conflicting/insecure
backups stay untouched. Retirement runs before systemd reload. Q-11 now
authorizes final Endeavour system build, realized-diff review and owner
`just switch endeavour` within inspected scope; unexpected changes reopen
approval. No reboot, rollback or other-host activation. Latest merge request
supersedes the prior no-Desktop-merge boundary only for work identified in scope;
it does not authorize merging unknown worktrees or bypassing required checks.
Q-13 selects RTK retirement, roaming recipe/daemon builders and sudo-PATH
reconciliation for reviewed PR publication, normal squash merge and Endeavour
delivery. Existing sudo-PATH source is already on main; no older V1 module is
copied. Other dirty worktrees and DNS/route approvals remain separate.
Q-14 accepts main #380's superseding Orion/Apollo pool, strict public pins,
LAN/tailnet aliases and one-job local fallback. Main's builder source/tests/CI
remain authoritative; this PR retains only independent RTK repair, fixture
correction and delivery records. The single additional thirty-minute candidate
build succeeded; its allowance is consumed, with no further retry authorized.
Q-16 accepts the inherited Endeavour Hermes CLI/interpreter/dependency update.
No guest uninstall or other-host activation.

## Evidence and bounded repairs

Earlier accepted-generation receipts cover real model → approved pwd → model
continuation and both configured MCPs on both backends. Those are historical,
not fresh paid-model/MCP execution after this repair. Repository CI at
`3d1d951` passed ten checks, including native tests and six host evaluations:
[run 38456124752](https://github.com/ErikBPF/desktop-nixos/actions/runs/38456124752).

Retirement/trigger assertions first failed RED. First implementation exposed
wrong `cmp` package ownership; corrected to diffutils. Independent review found
the pre-existing identical 0644-backup edge; assertion RED preceded exact-0600
guard GREEN. Hook-order assertion likewise failed before DAG correction.
All 29 workspace/backend tests, lint and formatting pass. Owner dry gate passes
with NixOS wrapper PATH restored; initial sudo error was executable selection,
not broken system permissions. No permission repair was attempted.

First user activation timed out during package-profile installation; no
activation process remained. Second owner-recipe attempt completed with longer
budget. Fresh receipts show both essential inventories active, zero failures,
matching native/API/unit PIDs, correct routes and unauthenticated 401. Backup
bytes match known legacy hash; V1 metadata and tmux checks pass. Current PIDs
are recorded in scratch receipts, not treated as permanent identities.

Earlier CI repairs realized missing dependencies, created scratch parents and
used absolute Python for the wrapper stub; runner failures were not behavioral
RED. Historical configured Donsetch returned Example Domain's heading/paragraph;
Nix returned programs.bash.enable type/default through model continuation.

## Continuing work, limits and recovery

Earlier retirement-only owner build failed unavailable SSH builders with local jobs disabled. Approved
candidate was then realized locally with one job. Independent realized review
against the then-current externally advanced system found unchanged kernel 7.2.6/systemd
261.2, all 111 HM package entries identical, no unrelated package-version update
or new unit, and only approved retirement/triggers plus source-reference rebuilds.
Six known system-unit differences remain. Both closures already contain native
V2 and approved Ponytail. This task held its switch on discovery of external
activation; new user request now requires worktree/merge reconciliation before
combined deployment. No system switch, reboot or rollback performed by this task.
Backend unit names remain; V1 executables were replaced, not whole units deleted.
Pre-reconciliation builder assertions observed RED/GREEN; all 15 focused tests passed.
Combined 29 workspace, 10 profile and five project tests pass, along with owner
lint/format/docs/fleet consistency and Endeavour dry build. Independent risk
review found no new verified defect; editorial review clarified historical
runtime receipts. These are local/static checks, not combined deployment proof.
See the [recovery integration record](../opencode-runtime-recovery/one-pager.md)
for daemon/recipe SSH policy, inherited builder-availability limits and historical
provider/DNS observations. PR #375's fe3f63e head passed eleven CI checks,
including GitGuardian. Two combined build attempts failed (timeout, then builder
transfer `Broken pipe`); attempt 3 built fb366a26 successfully. Main then advanced
through #378/#380/#379; old closure is not latest-main proof. Q-14 reconciliation
preserves main's replacement builder policy and Hermes source without activating
other hosts. For fb366a26, local gates and 72 focused checks passed. Header-smoke synthetic context
now matches the existing 100k roundtrip fixture; observed 10k overflow triggered
compaction, not the intended chat request. Assertions and production settings
remain unchanged; compaction injection is not claimed.
Q-14 head ddd8d0df passed 131 focused checks, lint/format/docs/fleet and Endeavour
dry. Its single authorized build realized system 80ikxlkix5dmmb5gywzw5h9y9fp6swl9
and HM 7drcpc1d1ivzv7kg9gxmy25p2nxm35gd. Head CI finished ten successful checks,
one skipped notification and one GitGuardian failure. External squash 80dafc8a
has exactly the built candidate tree; this task did not perform that merge.
Independent realized review confirmed builder/RTK scope and unchanged kernel/systemd,
but identified Hermes package metadata 0.21.3 to 0.0.0 (pinned source v0.21.7)
and Hermes Python 3.13.15 to 3.14.7. Q-16 accepts that additional local runtime
scope; compatibility is not proven by build success.

Branch sync now includes main through 264f8b66: #382 retains Ubuntu guest KACE
and removes its obsolete uninstall entry point; #383 changes Apollo supervision.
No host was activated here. Last observed running/booted Endeavour system remains
x7vf18qsd08slr05amqvpakb016y8ldj. Refresh candidate identity, dry validation,
realized scope and V1/session/window baseline before any future Endeavour switch.
Old 131-check/build receipts do not validate the newly synced head or live runtime.

Q-8's historical dashboard disposition remains unconfirmed. GitGuardian's occurrence
`303907955` flags an auth-file mode assertion, not a literal credential; no
exclusion, dismissal or history rewrite was applied. New incident 38245533 /
occurrence 304898809 was independently verified as a false positive at
`scripts/hermes-state-backup.sh:357` (temporary-file size check, not a secret).
User uninstalled GitGuardian; residual checks found no operational wiring in
inspected owners. Native Gitleaks/ripsecrets/secret scanning/push protection remain.
Historical failures remain records, not current deployment blockers. New sync-head
CI and post-switch behavior are not claimed.
Actual shortcut delivery, optional-plugin compatibility/quota/savings and bound
Gherkin completion remain unverified. MCP permissions are not argument/network
isolation. Credentials stay out of receipts and Git.

Discovery, first drafts, Q-9/Q-11 handoffs and pre/post receipts remain under
the approved `opencode-v2-migration-20261012` scratch directory. The
[session guide](../../guides/opencode-v2-sessions.md) records disabled experiments
and privacy limits.
