# Endeavour session recovery

**Stage / revision:** GREEN and runtime verification / 1
**Status:** Complete
**Owner / date:** desktop-nixos / 2026-11-22
**Basis:** “finish deploy. sessions are broken”

## Outcome and changes

Endeavour now runs generation 220, built from main revision `05fb90d5`.
The deployment used `just switch endeavour` after `just dry endeavour` passed.
Orion was the configured builder; Endeavour was the activation target.
The activated system is `/nix/store/gdnwagadn2h8hj6i3wy7d3srg8lq5d1y-nixos-system-endeavour-26.11.20261115.5c3cda7`.

Before deployment, both stopped OpenCode backends and the desktop tmux server
were started through the local user service manager. No implementation changes,
credential changes, session deletion, or database migration were performed.
This receipt lives in the dedicated `ops/endeavour-session-recovery-20261122`
worktree; deployment ran from the canonical checkout with its unrelated
untracked files preserved.

## Evidence and limits

Today's three earlier sudo rebuild records explicitly selected `.#endeavour`.
The 15:15 activation finished successfully and both backends resumed listening.
At 15:59:32 the journal recorded a broader desktop shutdown, including tmux,
window units, and both backends. Both backends exited with status 130. The
initiator of that desktop shutdown remains unidentified.

Post-deployment checks observed:

- `home-manager-erik.service` and `display-manager.service` active.
- User services `opencode-homelab`, `opencode-dataplatform`, and `desktop-tmux` active.
- Zero failed system units and zero failed user units.
- Authenticated native `opencode session list` calls succeeded on ports 4096
  and 4097, each returning three records with a three-record limit. Passwords
  were read into subprocess environments and never printed.
- `tmux -L workspace-desktop list-sessions` returned 15 workspace sessions.

Initial probes used obsolete HTTP paths and returned non-JSON responses;
these were not counted as health checks. Native V2 session queries supplied
application-level verification instead. Model generation and interactive
client reconnection were not exercised. Restored tmux sessions do not prove
that processes terminated during the earlier shutdown resumed their work.

## Decisions, remaining work, and recovery

The user authorized finishing deployment. No further approval is pending.
Recovery is complete at the service and session-history boundaries. Investigating
the earlier desktop shutdown is separate follow-up work. No automatic rollback
was performed; generation 219 remains the preceding system profile generation.


## Revision 2: repeated failure and identified cause

**Human seed:** “broken again. Redo. Check what is breaking process”

The first recovery restored availability but did not identify the trigger. At
16:35:23 both backends and the desktop services stopped again, with the system
still on generation 220. Home Manager file links changed at 16:35:18, without
a NixOS rebuild or invocation of the system Home Manager service.

A read-only query of the local OpenCode session records identified session
`ses_dfb472cbcffeIc9rB4a01TvDxj` running
`cd references/repos/desktop-nixos/worktrees/fix-sk-tty-20261122 && just home-switch endeavour 2>&1 | tail -40`.
Its generated Home Manager activation was
`/nix/store/mc8lxnrd9lqshmwjcp6v52ff2q2q797p-home-manager-generation`.
The backend exports isolated XDG state/data/cache roots. Home Manager uses
XDG_STATE_HOME to find its previous generation; the backend-local Home Manager
gcroots directory was empty. The activation therefore lacked the reference
needed to compare existing units.

The installed `sd-switch` reproduced the stop plan with `--dry-run` and only
`--new-units`: it planned to stop tmux, Ghostty, both OpenCode backends, and
other desktop services. Repeating the dry run with `--old-units` pointing at
generation 220's Home Manager unit directory planned no stops. No live stop
was performed by these diagnostic commands. The activation ran inside the
OpenCode service it stopped, preventing it from completing the restart phase.

Recovery restarted the existing system `home-manager-erik.service`, restoring
the deployed generation's files, then started the two backends and desktop
tmux. No changes in the other session's dirty worktree were discarded.

The task branch changes `home-switch` to use normal XDG paths and run the
activation as independent `home-manager-switch.service`, with a fixed name
preventing overlap through this entry point. The calling client may disappear,
but the service retains journal output and completes independently. The docs
now describe the enforced behavior instead of relying on callers to normalize
their environment manually.

RED: the new regression test failed because the recipe did not use an
independent service. GREEN: all 40 recipe tests passed; `just lint`,
`just fmt-check`, and `just docs-check` passed. The test exercises the real Just
recipe with mocked transport/build commands and isolated XDG paths; it does
not itself prove live service survival. Live validation follows below.

### Live verification and operational delivery

`just dry endeavour` passed. The corrected recipe was then exercised from the
canonical checkout with the backend's isolated XDG environment deliberately
supplied. At 16:41:31, `home-manager-switch.service` completed successfully
(exit 0; 3.915 seconds). Its journal planned only four starts and no stops.
Both backend PIDs (3870264, 3870263) and the tmux PID (3871202) remained
unchanged across activation. Authenticated native session-list calls returned
three records from each backend, 15 tmux sessions existed, and both system
and user failed-unit lists were empty. This verifies service continuity for
the reproduced XDG failure; it does not simulate killing the caller during
a genuine backend replacement or exercise model responses.

The safe recipe was copied, after exact baseline comparison, to the canonical
checkout and `worktrees/fix-sk-tty-20261122` as an operational backport. Only
`just/deploy.just` was changed there; the other session's dirty Nix modules
and tests were preserved. The complete patch, regression test, documentation,
and this receipt remain in `worktrees/endeavour-session-recovery-20261122`.
No commits or pushes were made. The canonical Graphify AST cache was updated.
Older worktrees still carry the unsafe recipe and must be updated before using
`home-switch`; this repair does not intercept arbitrary direct activation
commands or serialize full NixOS switches with user-only switches.
