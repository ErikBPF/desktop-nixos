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


Workspace-routing refinement (verbatim):

> check how we manage to open terminals on our current hyprland config. Follow the workspace logic to choose betwwen home, dataplatform and homelab. Copy logic for remote sessions. Based on folder we have a selection of alive sessions

Bare `sk` uses the same active-workspace project resolver as local terminal,
editor and file-manager launches. Workspaces 2–4 select
`/fast/compute/erik/Documents/nstech/dataplatform`; 5–12 select
`/fast/compute/erik/Documents/erik/homelab`; all others select `/home/erik`.
Outside Hyprland, bare `sk` selects remote home. An active but broken Hyprland
query fails rather than silently choosing another project. The existing project
ranges remain the single source of truth; compute paths derive from their
local Documents-relative paths. The remote picker shows only existing sessions
started in the selected folder, and defaults new sessions to that folder.
Explicit SSH commands, local editor/file-manager routing and the local terminal
escape hatch remain unchanged. No local folder-presence check gates remote use.

Boot defaults refinement (verbatim):

> check our kepler persistent sessions model and lets explore how to always start ol1-ol10 and ow1-ow10 sessions by default on start

> call l1-10 and w1-10 make l sessions auto start on homelab folder and w ones start on dataplatform

Accepted startup answer:

> Plain shells; launch agents manually (recommended)

At Kepler boot, provide detached sessions `l1`–`l10` starting in
`/fast/compute/erik/Documents/erik/homelab`, and `w1`–`w10` starting in
`/fast/compute/erik/Documents/nstech/dataplatform`. New defaults run plain
shells; agents are launched manually. Use the managed server and secure runtime
socket already used by `sk`, independently of desktop login.

Require the actual `/fast` mount and both existing project directories before
starting the managed server's restoration attempt. Missing storage or folders
fails visibly without creating project directories or choosing fallback paths.
The mount-ordered boot service is the server's sole declarative boot trigger.

Wait for the existing snapshot restoration attempt before filling missing exact
names. Preserve existing names, starting folders, unrelated sessions and running
panes. The existing policy for restoring selected commands remains unchanged;
restoration reconstructs state rather than preserving original processes/PIDs
across reboot. The seeder never starts a separate unmanaged server. Its stop or
restart leaves the managed server running. Deletion remains effective until the
next boot or explicit seeder restart. Local desktop sessions and the frozen
recovery configuration remain separate.
