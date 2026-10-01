# Independent workspace sessions: test contract

**Status:** Corrected behavior authorized, RED anchored in `593b697`, GREEN and live recovery verified on 2026-09-12. Renamed to sixteen plain-shell windows (w1–w8 / l1–l8) and review windows removed on 2026-09-20. tmux-resurrect persistence (restore at server start, systemd timer and shutdown saves) added on 2026-09-20.

Source: [human seed](behavior.md), [decision and plan](../../proposals/2026-09-12-local-workspace-sessions.md),
and [scenarios](workspaces.feature). The latest user correction supersedes grouped
Herdr panes and the coding-agent/review composition. Keep the original seed and
current live work intact.

## Public seams

- `desktop-workspaces bootstrap SESSION`, `recover`, `save`, `restore`, and
  `launch shell|nvim|yazi`.
- Config: existing project/root/workspace mapping, per-project window `prefix`/`count`,
  explicit `shell` path, and the resurrect plugin/directory.
- `python3 -m unittest discover -s tests/local-workspace-sessions -v` binds behavior
  and evaluated Nix configuration. `smoke.py` uses an isolated native tmux server
  and no real applications. No Gherkin parser or new test framework.

## Examples and invariants

| Scenario | Input | Observable result |
| --- | --- | --- |
| Independent default windows | Each project, prefix+1..8 | Sixteen exact named sessions; one initial pane each; correct project cwd |
| Attach by name | `w1`/`l1` alias | Attaches the local session, creating it once via bootstrap if absent |
| Preserve existing work | Existing exact named session, arbitrary layout/cwd | No new-session, kill, respawn, rename, send-keys, or layout replacement |
| Backend ownership | Backend unavailable, then ready | Bounded show-options polling; every call uses -N and the dedicated socket |
| Routing | IDs 2–4, 5–12, negative/special/outside | Work root, lab root, previous behavior respectively; mapped Yazi receives root directly |
| Recovery | Login/shortcut repeated or concurrent | Same sixteen frontend unit names; one process/window per unit; no application restart |
| Missing root | Project directory absent | Fail before tmux commands; do not create repos or silently use another root |
| Application exit | Shell exits normally | Session persists; no automatic restart |
| Reboot persistence | Snapshot present, then server start | Restore runs in-server before window bootstrap; saves target the dedicated socket; absent snapshot is a no-op |
| Safe transition | Existing four Herdr backends | Same unit names and keep-old; old attachment clients may close, backends survive |

The dedicated backend is `tmux -D -L workspace-desktop -f CONFIG`, without an
extra command after `-D`. All clients/coordinator calls use `tmux -N -L workspace-desktop`.
Readiness checks the server, not whether it already has sessions. Match session
names exactly with `has-session -t =NAME`; creation is detached in an explicit cwd.
Every session is a plain shell; no session starts an application.

Evaluated units must contain one tmux backend and sixteen frontend services.
Frontends Require/After the backend, initialize in ExecStartPre, and never restart
on close. Backend has keep-old and no graphical/frontend PartOf/BindsTo. Its
config prevents exit on empty/unattached sessions. Retain four old Herdr backend
units with keep-old; no old Herdr frontend units remain. Only Endeavour opts in.

The backend restores the last resurrect snapshot in ExecStartPost, before any
frontend ExecStartPre bootstrap. `save`/`restore` run resurrect scripts inside
the dedicated server via `tmux -N -L workspace-desktop run-shell`, so the default
tmux socket is never touched. A periodic timer and a shutdown-ordered unit call
`save`; both are no-ops when the server is down.

## Limits and verification

Frontend close/logout preserves processes. Reboot restores the last snapshot
(timer interval and clean-shutdown timing bound what is captured); an absent or
failed restore falls back to the declarative recreation of default sessions.
Native smoke must not use real credentials
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
