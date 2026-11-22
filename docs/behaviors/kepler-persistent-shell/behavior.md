# Persistent Kepler shell

**Status:** Implementation slice from accepted thin-client behavior.

Human seed:

> we want to make this computer as much as possible into a "thin client" for development. We should have some sort of tooling that would make terminals open by default on a remote machine. THere we can run persistent sessions. Those can be used to run agents or simple terminals. Whenever something like a webapp is run locally or we need to do a device login we can portforward between machines. Something like a fake localhost

Accepted answers:

> Kepler by default; local escape hatch

> Automatically forward ports for selected projects

Human refinement:

> we should have something like the /resume comand to cycle through oppened tmux sessions based on the folder and attach to it

Latest accepted instruction:

> open on picker. Also add the possibility to delete older sessions or start new ones

Bare `sk` and Super+T open Kepler's session picker. Rows show starting folder,
name, attached/detached status and creation time. Search or use arrows; Enter
attaches the selected session. `tmux-resume [folder]` also works on Kepler; its
optional filter matches the canonical starting folder, not a pane's changing cwd.
Inside tmux, attachment switches clients without nesting. Escape cancels.

The New session row and Ctrl-N prompt for an existing starting folder and an
optional name, create a detached session and attach it. The default folder is
`/fast/compute/erik/Documents`, or the supplied folder filter. Duplicate names
and invalid folders produce errors without replacing existing sessions.

Ctrl-D on a session prompts for the exact word DELETE and warns that its running
processes will terminate. The selected session's server PID, creation timestamp
and session ID are checked atomically before deletion. A stale picker cannot
kill a replacement session reusing the same ID. Session deletion does not delete
project files. No automatic age-based expiry occurs. The list refreshes after a
delete or declined confirmation; Ctrl-D on New session is harmless. Deleting
the session running the picker also terminates that picker.

Explicit `sk <arguments>` retains SSH passthrough. Super+Shift+T stays local.
Connection failures never create local fallback writers. No agents start
automatically. Session processes survive client disconnection, not Kepler reboot.
