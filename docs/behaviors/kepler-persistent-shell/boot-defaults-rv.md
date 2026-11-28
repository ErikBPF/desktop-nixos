# Kepler default sessions: review and delivery

**Status:** Local RV complete; CI and deployment verification pending. No deployment or reboot performed.

## Outcome and accepted behavior

At boot, Kepler fills missing `l1`–`l10` names with detached plain shells in
`/fast/compute/erik/Documents/erik/homelab`, and missing `w1`–`w10` names in
`/fast/compute/erik/Documents/nstech/dataplatform`. Agents remain manual. Existing
matching names keep their starting folders. Rerunning the seeder preserves
existing session IDs and running panes. The verbatim [human seed and
correction](behavior.md) remain the acceptance source.

## Review findings and revision

The first draft used stale baseline `05fb90d5`. Fresh source at `8051ddcb` already
contains managed tmux and snapshot restoration. Three independent reviewers
covered conformance/correctness, security and other applicable CodeHero risks,
and document structure/prose plus simplicity. Four verified findings were fixed:

| Finding | Resolution |
| --- | --- |
| The first draft selected a different socket from SSH clients. | Set `TMUX_TMPDIR` to the same user runtime directory as the managed server. Test the real default socket without forcing `-S`. |
| Seeding could race snapshot restoration or create a competing server. | Wait for `systemctl --user start kepler-tmux.service`; fill only through `tmux -N`. Remove independent scopes. |
| The existing user boot trigger could restore before the nofail `/fast` mount. | Make the mount-ordered system service the sole declarative boot trigger; validate both directories before starting restoration. |
| Extending the shared development module unnecessarily changed frozen recovery. | Put defaults in the existing ordinary-Kepler persistence module. Leave recovery and its exact containment fixture unchanged. |

The proposed sessionless-server detection bug was discarded after a real-tmux
probe confirmed the existing detection succeeds. No additional security or
performance defect was verified; accessibility is not applicable. Final code
review found no remaining actionable correctness or specialist finding.

## Evidence and limits

The revised RED anchor had two assertion failures for the absent boot unit while
three existing persistence checks passed. The initial revised GREEN passed all
five checks. The real-tmux test covers twenty names, starting folders and actual
pane directories; missing folders; owner failure/absence without fallback;
restoration before filling; a restored `l1` in another folder; and preservation
of unrelated sessions, IDs and pane PIDs. CI explicitly provides tmux so this
coverage cannot silently skip.

Final validation passed 46 tests: persistence (5), SSH routing (7), local
workspaces (21), and picker behavior (13). Lint, full formatting, ShellCheck,
documentation links, whitespace checks and the ordinary Kepler toplevel dry
build passed. The dry build used `--offline`, so it establishes evaluation and
build planning rather than cache availability or realized builds.

A disposable system-service/user-service integration also passed: all twenty
names and directories were checked, restored `l1` kept its folder, and seeder
restart/stop preserved every session and pane PID. Its restore operation was a
fixture; real boot, mount ordering and successful resurrect recovery remain
deployment checks. The existing ignored restore-error policy is unchanged.
Old scope probes are not evidence for this replacement implementation. The
unchanged historical recovery incident contract is outside this final slice.

The frozen draft, snapshot manifest, RED/GREEN and final suite logs, offline dry
log and `managed-lifecycle.json` are retained locally under
`~/.local/state/kepler-default-sessions/rv-20261127-ovm46tvq/`.

## Operations and recovery

Both project directories are mandatory: a missing directory blocks managed
restoration as well as default creation. A switch may start the new system unit;
an already running server remains intact. Stopping or restarting the seeder does
not stop the separate managed user service. Roll back the module revision to
restore its prior boot trigger. Snapshot reconstruction does not preserve the
original process IDs across reboot. No merge or deployment is part of this PR.
