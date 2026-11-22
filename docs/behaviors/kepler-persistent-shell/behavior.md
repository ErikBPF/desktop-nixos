# Persistent Kepler shell

**Status:** Implementation slice from accepted thin-client behavior.

Human seed:

> we want to make this computer as much as possible into a "thin client" for development. We should have some sort of tooling that would make terminals open by default on a remote machine. THere we can run persistent sessions. Those can be used to run agents or simple terminals. Whenever something like a webapp is run locally or we need to do a device login we can portforward between machines. Something like a fake localhost

Accepted answers:

> Kepler by default; local escape hatch

> Automatically forward ports for selected projects

This slice implements only persistent plain shells: bare `sk` and Super+T attach
the same `development` tmux session on Kepler, creating it under
`/fast/compute/erik/Documents` if absent. Closing the terminal or disconnecting
the client preserves processes; rebooting Kepler does not. Additional sessions
can be created with tmux on Kepler. `sk <arguments>` preserves its existing SSH
passthrough behavior, and Super+Shift+T stays local. Connection failures remain
errors, never automatic local writers. No agents launch automatically.
