# Kepler session picker

**Status:** Final behavior validated and independently reviewed; not deployed.

## Outcome and decisions

Bare `sk` and Super+T open a folder-based picker of Kepler's tmux sessions.
The user explicitly replaced the earlier shared-session default with this picker
and requested new-session and old-session deletion actions. The verbatim seed
and corrections remain in `behavior.md`. Explicit SSH arguments and the local
Super+Shift+T escape hatch remain unchanged.

Rows show starting folder, name, attachment status and creation time. Enter
attaches; inside tmux it switches the current client. Ctrl-N or New session
prompts for folder and optional name. Ctrl-D requires typing DELETE after a
warning about terminating running processes. Deletion checks server PID and
session creation time atomically because tmux reuses IDs after server restart.
Files are never deleted. Escape cancels; no automatic session expiry occurs.

## Implementation boundaries

Use the existing tmux and fzf packages, with a small Python helper. Clear fzf's
default-option variables so user defaults cannot silently select a session.
Identify sessions by tmux IDs, not names or folder basenames; optional folder
filtering uses canonical full paths. No session registry, filesystem crawling,
automatic agent launch or forwarding-policy change is needed. Kepler enables
tmux and Ghostty terminfo. Existing lingering and `KillUserProcesses=false`
support disconnect persistence; host reboot persistence remains out of scope.

## Evidence and revision

The initial launcher and server-option tests failed before implementation; the
first green slice passed 33 workspace tests. The resume-only refinement passed
six picker tests and a real local PTY search/attach/detach check. The initial
PTY harness failed with its unsupported terminal type; using xterm-256color
fixed that harness without changing production code.

For the current behavior, the updated launcher assertion failed against the
old shared-session command. New create, empty-server and delete tests failed
against the resume-only helper. Twelve picker tests now pass, including explicit
confirmation, harmless Ctrl-D on New, no automatic fzf selection, failure
handling and a real two-server test proving a reused session ID is protected.
A disposable PTY test created a named session, attached, detached, deleted it
with confirmation, returned to the empty picker and retained a sentinel file.
Only the isolated test servers were removed.

Independent review identified stale server IDs and Ctrl-D on New as risks;
both were fixed with regression coverage. Final validation passed all 12 picker tests and 33 workspace tests, lint,
formatting, docs and both host dry builds.
The actual interactive remote deployment remains unverified.

## Delivery and remaining work

PR #511 delivered and activated the synchronized Documents directory. PR #512
owns this picker and will be updated around the final behavior, with CI and a
fresh review required for its new head. Activate Kepler's package before the
client shortcut. Endeavour's separate Home Manager collision with the voice
Hyprland configuration is still preserved pending the user's decision; no
picker activation is claimed. Git metadata, agent credentials and automatic
project forwards remain later thin-client work.

Rollback restores plain SSH in `sk` and leaves existing remote sessions intact.
