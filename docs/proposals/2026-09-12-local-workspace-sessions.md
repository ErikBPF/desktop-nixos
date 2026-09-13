# Independent local workspace sessions

**Status:** Implemented, reviewed, and activated on Endeavour on 2026-09-12.

## Human seed and correction

The [human seed](../behaviors/local-workspace-sessions/behavior.md) preserves the
user's messages verbatim. The initial implementation grouped eight panes into
one Herdr window. After activation the user clarified: “the 8 windows show be
independet tmux sessions”. That correction supersedes the grouped Herdr design.
The new unit of work is one desktop window attached to one named tmux session.

| Workspace | Project | Independent windows and tmux sessions |
| --- | --- | --- |
| 2 | dataplatform | dataplatform-agent-1 through -6; dataplatform-shell-1 and -2 |
| 3 | dataplatform | dataplatform-tuicr; dataplatform-nvim |
| 7 | homelab | homelab-agent-1 through -6; homelab-shell-1 and -2 |
| 8 | homelab | homelab-tuicr; homelab-nvim |

This makes twenty windows and twenty sessions. Each new session starts with one
pane. Code workspaces contain six coding-agent windows and two shell windows.
Review applications also get independent windows and sessions. All execution is
local on Endeavour. Project roots remain `~/Documents/nstech/dataplatform` and
`~/Documents/erik/homelab`. Desktop shell/Neovim/Yazi shortcuts still choose work
on workspaces 2–4 and homelab on 5–12; other workspace behavior is unchanged.

## Grounded grill, decision map, and ADR

- Q-1: Does “8 windows” permit eight panes in one window? No. The correction
  explicitly requires independent tmux sessions; replace the grouped layout.
- Q-2: Can each frontend start its own daemon? A daemon created under a frontend
  service can remain in that service's cgroup and be killed when the window
  closes. One foreground tmux server, managed by a separate user service, owns
  twenty independent sessions. This shares the native server, not session focus.
- Q-3: Can we delete the old Herdr service declarations? No. Home Manager's
  `sd-switch` stops removed units even when their old `X-SwitchMethod` is
  `keep-old`. Retain the four existing backend definitions, without autostart,
  so the deployed agents and editors remain available during the transition.
- Q-4: What happens when a coding agent or editor exits? Return that window to
  an interactive shell; do not automatically restart the application. Recovery
  preserves an existing session, including changed directories and extra panes.

Product: “Eight windows means eight independently attachable working sessions.”
Architect: “Use tmux's named sessions and a dedicated socket. No custom session
registry and no backend per window.” Operator: “Attach clients must use `-N`, so
an unavailable backend cannot silently create a daemon in the frontend cgroup.”
Security: “Quote configured executable paths and preserve old Herdr processes;
never add permission-bypass flags or replace existing sessions.”

Accepted implementation decisions:

- `desktop-tmux.service` runs `tmux -D -L workspace-desktop -f CONFIG`. The
  dedicated config sources the existing user tmux config, then disables
  `exit-empty`, `exit-unattached`, and `destroy-unattached`.
- All coordinator and frontend commands use `tmux -N -L workspace-desktop`.
  Readiness uses server-only `show-options -s exit-empty`; an empty session list
  is not a server-readiness failure. Exact session lookup uses `has-session -t =NAME`.
- Twenty systemd frontend services create missing sessions, then attach Ghostty.
  Systemd serializes repeated or concurrent starts of each frontend. Stable
  application classes place the windows on 2, 3, 7, and 8.
- `defaultCodingAgent` is an installed executable, initially `codex`. The shell
  path is explicit. Agent and review commands return to that shell on exit.
- Login and Super+Shift+R call the same recovery command. Import only required
  graphical environment, synchronously, before starting the frontend services.
- The tmux backend has `X-SwitchMethod = "keep-old"`; it has no graphical or
  frontend lifetime dependency. Endeavour user lingering retains it after logout.
- Old Herdr frontend declarations are removed, which closes their clients; four
  old backends remain declared and running. Their work is available via
  `herdr --session dataplatform-code`, `dataplatform-review`, `homelab-code`, or
  `homelab-review`. Retiring those backends requires a deliberate later action.

Rejected: one tmux server per window, eight panes in a shared session, reusing the
unrelated default tmux socket, auto-respawning applications, and stopping old
backends merely to clean up the screen. The existing `tmux-repo` helper is not
used because it imposes a grouped layout and permission-bypass flags.

Persistence covers frontend close and logout while the computer remains running.
A reboot stops tmux processes; the next login creates fresh default sessions.
This change does not add tmux session resurrection or recover unsaved editor data.

## Implementation plan and test seams

The [test contract](../behaviors/local-workspace-sessions/test-contract.md) and
[feature scenarios](../behaviors/local-workspace-sessions/workspaces.feature)
bind the correction to observable checks.

1. RED: replace grouped-Herdr expectations with twenty independently named tmux
   sessions, one initial pane each; verify exact lookup, no daemon autostart,
   configured agent command, and existing-session preservation. Keep folder
   routing and graphical-environment checks. Commit the RED anchor.
2. GREEN: replace native Herdr initialization with native tmux initialization;
   retain the small Python coordinator. Expand the Nix frontend map to twenty
   entries, add one foreground tmux service, and preserve the four old Herdr
   backends. No shared profile or remote-session changes.
3. Review independently for conformance, quoting, server/frontend ownership,
   old-backend preservation, command-exit behavior, and simplicity. Verify the
   native tmux API with harmless executable shims and an isolated socket.
4. Run focused tests, existing startup tests, lint, formatting, docs and structure
   checks, and Endeavour dry-build. Deploy via the existing recipe, then verify
   twenty windows, twenty sessions, twelve real Codex processes, review apps,
   repeated recovery, and unchanged old Herdr backend PIDs.

The coordinator seam tests branching and argv; evaluated Nix tests verify wiring
and scope; isolated native tmux tests verify actual session/process behavior.
Mocks do not prove graphical placement or real agent startup. Cap repairs at
three attempts for a failing verification; do not modify unrelated dirty files.

## Deployment and rollback

The first implementation was activated with `just home-switch endeavour` after
confirming `loginctl show-user erik -p Linger` reported `yes`. Eighteen foreign
Codex-tools skill links blocked Home Manager's first collision check; the exact
links were preserved under
`~/.local/state/workspace-sessions/backups/home-manager-1d3ddqjh` before retrying.
No skill contents were deleted. The second activation succeeded.

Use the same recipe for the tmux correction: user lingering is already enabled,
so an OS switch is unnecessary for this deployment. A future system deployment
also declares that setting. Do not restart the preserved Herdr or tmux backend
when activating a new frontend configuration. Rollback must preserve both backend
services and their session data; closing attachment windows is safe, stopping
servers interrupts their jobs.

## Verification record

Initial Herdr version: RED anchor `de2e4c9e`; 15 focused/evaluated checks, four
startup tests, native layout smoke, launcher build, and Endeavour dry-run passed.
Activation showed four correctly placed windows and twelve ready Codex agents;
real tuicr and Neovim were present in both review sessions. Repeated recovery kept
all PIDs and window identities. This validated the old implementation, not the
user's corrected independent-window requirement.

Corrected tmux version: RED anchor `593b697`; eleven behavior tests, four
configuration checks, and the isolated native tmux smoke pass. `just lint`,
`just fmt-check`, `just docs-check`, `just structure-check`, and the Endeavour
system build dry run pass. Independent lifecycle, security, correctness, and
simplicity review found no remaining issues.

`just home-switch endeavour` activated the corrected configuration successfully.
Live verification found twenty independent one-pane tmux sessions and twenty
Ghostty windows: eight on workspace 2, two on 3, eight on 7, and two on 8.
Process metadata confirms twelve Codex processes, two tuicr sessions, two Neovim
sessions, and four plain shells, all rooted in their assigned projects. The
shell wrapper can make tmux's `pane_current_command` report `zsh`; process
descendants are the authoritative application check.

Repeated recovery preserved all twenty window addresses and pane IDs/PIDs.
Stopping and recovering `desktop-window-homelab-shell-2.service` preserved every
pane process. All four previous Herdr backend PIDs and pane IDs remain unchanged.
Native tmux places pane processes in `tmux-spawn-*.scope` units with
`PartOf=desktop-tmux.service`; they do not belong to frontend lifetimes. Hyprland
reports no configuration errors. Login startup and Super+Shift+R are installed;
a fresh logout/login was not forced during this active desktop session.


## Initial window placement

The user's grid request initially led to a native Lua grid. Although it arranged
all eight windows evenly, it left an unused cell when a window closed. The user
then clarified that the default layout should remain in control and placement
should use Hyprland commands. This supersedes the custom grid implementation.

Keep `dwindle`. On initially empty project workspaces, start windows sequentially,
focus the largest tile, and use `hyprctl dispatch 'hl.dsp.layout("preselect r")'` (or `d`)
to split its longer dimension. Lua-mode Hyprland requires Lua dispatcher
expressions; the legacy `layoutmsg` CLI syntax is rejected. This creates a balanced initial arrangement and
lets native dwindle reclaim space after later closes. No custom layout or extra
daemon is needed. Existing workspace recovery does not rearrange the user's
windows; initial startup restores the original focus and bounds readiness waits.

For the transition, native floating/tiling dispatches can rebuild the current
window tree once without restarting terminal processes. This is an explicit
rollout action, not part of ordinary recovery.


Verification: twenty focused checks pass, including fresh placement, moved-window
preservation, concurrent recovery lock contention, bounded timeout cleanup, and
focus restoration. Lint, formatting, documentation links, and the Endeavour
system dry build pass. Review findings about simultaneous recovery and windows
moved elsewhere were fixed and covered by regression checks.


The corrected Lua-mode commands were activated with `just home-switch endeavour`.
Live verification confirms `dwindle` on all four workspaces, eight balanced tiles
on workspace 2, seven space-filling tiles on workspace 7, and side-by-side review
pairs. Every row reaches the same left and right edges without an empty cell.
All twenty tmux pane IDs/PIDs survived; Hyprland reports no configuration errors.
Fresh-login placement is covered by tests and live dispatcher smoke checks;
a logout/login was not forced during the user's active session.
