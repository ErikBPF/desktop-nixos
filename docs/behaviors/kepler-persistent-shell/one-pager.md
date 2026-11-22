# Persistent Kepler shell

**Status:** Local validation and independent review passed; not deployed.

## Outcome and decisions

The terminal shortcut currently opens an ordinary SSH shell. Bare `sk` now
reattaches a plain tmux session named `development`, initially rooted in the
synchronized Documents directory. The session persists across client disconnects;
Kepler reboot persistence is outside this slice. Explicit SSH arguments preserve
the old behavior, including remote commands and exit status.

Use NixOS's existing tmux module on Kepler, with host identity in the status bar.
Install Ghostty's terminfo output because the remote host currently lacks
`xterm-ghostty`; this avoids changing terminal identity or installing a GUI.
Kepler's user already has lingering enabled. Do not import the desktop tmux
helpers: they carry fixed layouts and automatic agent launch behavior.

## Evidence and delivery

The regression test executed the evaluated launcher with a capture-only SSH
substitute. RED: bare launch omitted tmux and the server's tmux option was false;
explicit command forwarding and SSH error propagation already passed. GREEN,
host dry builds, full workspace suite and independent review follow. The initial directory depends on the Syncthing paths delivered by merged PR #511.

## Boundaries and recovery

This does not migrate Git metadata, credentials, agents or editor configuration,
and does not change forwarding policy. Multiple bare `sk` windows attach the same
session; separate sessions remain an explicit tmux action. Existing sessions are
never killed or reshaped. Revert the launcher to plain SSH to roll back; leave
remote sessions intact. The voice Hyprland collision remains a separate pending
user decision and must not be silently overwritten during activation.


## GREEN and independent review

All 33 tests in `python3 -m unittest discover -s tests/local-workspace-sessions -v`
passed. After review, the four focused launcher tests were rerun with assertions
for `KillUserProcesses=false` and Ghostty terminfo presence; all passed. Lint,
formatting and documentation checks passed. Both host toplevel dry builds passed.
The independent reviewer found no blocking issues and confirmed the source and
evaluated logind policy support disconnect persistence. Runtime detach/reattach
has not yet been exercised; capture-only launcher tests do not claim that proof.

The final implementation is twelve added configuration lines, plus regression
tests and this record. No session manager, automatic agents, desktop helper
imports or new forwarding policy were introduced.


## Folder-based resume refinement

The user requested cycling through open sessions by folder. Added a remote
`tmux-resume [folder]` helper using the existing tmux and fzf packages. It sorts
by starting folder and session name, displays attachment status, and selects by
stable tmux session ID. Cancellation leaves sessions untouched; running inside
tmux switches the current client. Exact full-path filtering distinguishes
projects sharing a basename. No session registry or filesystem crawler is needed.

The native `session_path` field was verified with two disposable local tmux
sessions in different folders with the same basename; that test server was
removed afterward. Unit tests cover selection, cancellation, exact folder
filtering, nested-session avoidance and unknown IDs. An independent reviewer
found inherited fzf options could auto-select unexpectedly; an assertion-failing
regression was added and fixed by clearing only fzf's two default-options
variables for the picker process. Interactive remote use remains unverified.

Pending async question: bare-sk picker versus explicit sk-resume entrypoint.
The current published checkout is the persistent-shell worktree, and the existing
launcher remains unchanged while that answer is pending. The helper is available
through `sk -t tmux-resume` after deployment; no production activation has occurred.


Picker validation: six unit tests pass; lint, formatting, docs and the changed
Kepler toplevel dry build pass. A disposable local PTY check with two sessions
sharing the folder basename `project` searched for `home`, attached that session,
and detached with both sessions still present (`RESUME_INTERACTIVE_OK`). The first
attempt failed because the harness advertised an unsupported terminal; rerunning
with `TERM=xterm-256color` passed without production code changes. Remote Kepler
activation remains untested. The independent review finding is fixed and covered
by the fzf-defaults regression. No sessions outside the temporary test server
were touched.
