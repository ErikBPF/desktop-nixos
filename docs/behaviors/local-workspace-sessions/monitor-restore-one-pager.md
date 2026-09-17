# Workspace monitor recovery and reboot restoration

**Stage / revision:** GREEN and live verification / 1
**Status:** Monitor correction deployed; reboot restoration awaits clarification.
**Owner / date:** desktop-nixos / 2026-09-14
**Checkout:** `/home/erik/Documents/erik/desktop-nixos`, HEAD `765aec34` plus working-tree changes.
**Basis:** [Existing contract](test-contract.md) and the user's correction below.

> our windows to workspace 2 are not in the right monitor. Check and lets fix. Also sessions did not restart from where we stoped

## Outcome and changes

Workspace 2 was on the left portrait display, DP-3, although its existing rule assigns it to the central Samsung QBQ90. It was moved to HDMI-A-1 without restarting applications. The monitor module now recovers workspaces 1–9 on startup and when that display reconnects. Existing workspace 10 recovery remains intact.

The machine rebooted at 07:39; all twenty desktop tmux sessions were created around 07:40. The current launcher starts fresh applications. The existing contract explicitly preserves processes across frontend closure/logout, but excludes reboot restoration. No session restoration behavior or acceptance was changed.

## Evidence and limits

- The added structure assertion failed before implementation. An earlier pytest invocation lacked pytest; that infrastructure failure is not RED.
- All ten structure checks passed through Python's `runpy`; `just lint`, `just fmt-check`, `git diff --check`, and Endeavour's toplevel Nix dry-run passed.
- `just home-switch endeavour` was launched. Its terminal receipt was lost during interruption; subsequent inspection confirms the deployed Lua includes both recovery handlers at `/nix/store/1350a0lmaz4x6wx5pa2bfb14x5mf60ch-hm_hyprhyprland.lua`.
- Live Hyprland reports no configuration errors and workspace 2 on HDMI-A-1. The desktop tmux server remains active with PID 4745, unchanged from before deployment.
- Structure checks are static, not a simulated hotplug test. Neither reboot nor physical monitor reconnection was performed.

## Continuing and waiting work

**Q-1, pending:** Which missing state should return after reboot: agent conversations, terminal/editor state, or both? Asked through the native asynchronous question tool; no answer recorded. This question is bound to this checkout and page revision; no separate review session exists.

Recommendation: restore each agent window's own conversation identity, and explicitly define any editor/shell restoration. Six agents share each project directory, so a shared `codex resume --last` would select the wrong conversation for multiple windows. Existing saved metadata does not provide a reliable old window-to-thread mapping. Implementing restore waits for scope clarification; silence is not approval.

Unrelated pre-existing and concurrent working-tree edits were preserved. No commit or push was made. To undo this monitor change, revert only this task's monitor handler and associated structure assertions, then use `just home-switch endeavour`; do not stop the tmux backend.
