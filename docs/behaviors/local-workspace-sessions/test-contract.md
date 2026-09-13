# Independent workspace sessions: test contract

**Status:** Corrected behavior authorized, RED anchored in `593b697`, GREEN and live recovery verified on 2026-09-12.

Source: [human seed](behavior.md), [decision and plan](../../proposals/2026-09-12-local-workspace-sessions.md),
and [scenarios](workspaces.feature). The latest user correction supersedes grouped
Herdr panes. Keep the original seed and current live work intact.

## Public seams

- `desktop-workspaces bootstrap SESSION`, `recover`, and `launch shell|nvim|yazi`.
- Config: existing project/root/workspace mapping, `defaultCodingAgent` executable,
  and explicit `shell` path.
- `python3 -m unittest discover -s tests/local-workspace-sessions -v` binds behavior
  and evaluated Nix configuration. `smoke.py` uses an isolated native tmux server
  and harmless agent/review executables. No Gherkin parser or new test framework.

## Examples and invariants

| Scenario | Input | Observable result |
| --- | --- | --- |
| Independent default windows | Each project, agent-1..6, shell-1..2, tuicr, nvim | Twenty exact named sessions; one initial pane each; correct project cwd |
| Configurable agent | Alternate installed executable | Six code sessions per project run that executable; no permission-bypass flags |
| Preserve existing work | Existing exact named session, arbitrary layout/cwd | No new-session, kill, respawn, rename, send-keys, or layout replacement |
| Backend ownership | Backend unavailable, then ready | Bounded show-options polling; every call uses -N and the dedicated socket |
| Routing | IDs 2–4, 5–12, negative/special/outside | Work root, lab root, previous behavior respectively; mapped Yazi receives root directly |
| Recovery | Login/shortcut repeated or concurrent | Same twenty frontend unit names; one process/window per unit; no application restart |
| Missing root | Project directory absent | Fail before tmux commands; do not create repos or silently use another root |
| Application exit | Agent/editor exits normally | Interactive shell remains; no automatic application restart |
| Safe transition | Existing four Herdr backends | Same unit names and keep-old; old attachment clients may close, backends survive |

The dedicated backend is `tmux -D -L workspace-desktop -f CONFIG`, without an
extra command after `-D`. All clients/coordinator calls use `tmux -N -L workspace-desktop`.
Readiness checks the server, not whether it already has sessions. Match session
names exactly with `has-session -t =NAME`; creation is detached in an explicit cwd.
Shell commands quote each executable/path. Shell-only sessions do not start agents.

Evaluated units must contain one tmux backend and twenty frontend services.
Frontends Require/After the backend, initialize in ExecStartPre, and never restart
on close. Backend has keep-old and no graphical/frontend PartOf/BindsTo. Its
config prevents exit on empty/unattached sessions. Retain four old Herdr backend
units with keep-old; no old Herdr frontend units remain. Only Endeavour opts in.

## Limits and verification

Frontend close/logout preserves processes; reboot does not. Fresh login after a
reboot recreates the default sessions. Native smoke must not use real credentials
or real project checkouts. Live acceptance checks actual process names/readiness
without reading terminal text or prompts. Check no duplicates by comparing unit
PIDs and window IDs before/after recovery. Preserve old Herdr PIDs during rollout.

Required checks: focused and native tests, existing startup tests, `just lint`,
`just fmt-check`, `just docs-check`, `just structure-check`, and Endeavour dry-build.
No local full-flake check. Deploy with `just home-switch endeavour` while existing
lingering remains enabled. No backend stop or session deletion during rollback.


## Initial placement follow-up

- Keep Hyprland's default dwindle layout; remove the custom Lua grid.
- During initial startup on an empty project workspace, open windows sequentially.
  Before each additional window, focus the largest existing tile and use native
  `hyprctl dispatch 'hl.dsp.layout("preselect r")'` (or `d`) to split its longer dimension.
- Eight initial windows form a balanced arrangement; subsequent closes and opens
  follow normal dwindle behavior without fixed empty cells.
- Recovery preserves occupied workspaces and groups whose windows were moved
  elsewhere. Concurrent recovery is serialized with a runtime file lock.
- Window discovery is bounded; restore the previously focused window/workspace
  after initial placement, including failure paths.
- Existing monitor assignments and independent tmux process identities survive.
