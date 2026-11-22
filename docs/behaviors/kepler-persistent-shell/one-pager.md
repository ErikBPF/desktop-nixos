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
host dry builds, full workspace suite and independent review follow. Publication
stacks on the Syncthing PR because the initial directory depends on those paths.

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
