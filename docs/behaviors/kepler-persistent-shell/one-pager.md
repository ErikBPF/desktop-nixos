# Kepler session picker

**Status:** PR #512 merged and activated; live listing regression found and fixed, follow-up rollout pending.

## Outcome and decisions

Bare `sk` and Super+T open a workspace-scoped picker of Kepler's tmux sessions.
Workspaces 2–4 select dataplatform, 5–12 select homelab, and other workspaces
select remote home. Both local and remote routes share the same workspace
resolver; project compute paths derive from the existing local Documents paths.
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


## Workspace routing receipt

Live Hyprland still uses the earlier Ghostty → sk shortcut, bypassing the
workspace router; nvim and yazi already use that router. The revision makes
bare sk delegate to `desktop-workspaces remote`, sharing `active_project` with
local launches. SSH gets an explicitly quoted remote picker command and full
folder path; remote folders need not exist locally. No Hyprland environment
uses remote home, while a failed active-desktop query remains an error.

The three destination directories were verified on Kepler. RED checks caught
the missing route and old bare-sk invocation before implementation. Boundary
tests cover workspaces outside and across both configured ranges, paths with
spaces, non-desktop launches and query failure. The existing local routing
checks remain intact. Final validation passed 36 workspace tests and 12 picker tests, lint,
formatting, docs and the changed Endeavour toplevel dry build. Independent review
found no blocking issues. The generated Nix manifest was checked against all
three expected destinations (`GENERATED_REMOTE_ROUTES_OK`); the first two check
attempts needed correction for Nix's versioned `derivations` wrapper and
`structuredAttrs` layout, without production changes. Live shortcut activation
remains pending.


## Apply preparation — recovery target

The user authorized merge and activation, then explicitly accepted backing up
the temporary voice Hyprland config and temporarily losing Super+F8/F9/F10.
Readback found Kepler has since moved to the published cp-1 containment host
`492mc5...`, so ordinary Kepler deployment would overwrite the recovery setup.
The same development-tools block is now a shared `kepler-development` module
imported by both ordinary Kepler and `kepler-cp1-recovery`. The pinned recovery
baseline, cp-1 override and disabled boot counting remain unchanged.

The new regression failed because recovery tmux was disabled; all five focused
launcher/recovery tests now pass. Use the existing `deploy-preview` and `deploy`
recipes on the recovery target, as its owner documentation requires. Compare
the generated installer, kernel/modules, VM PIDs/start times and boot defaults
before/after. Do not use deploy-rs here: its bootloader rewrite conflicts with
containment. The old boot ID, all six VM PIDs and start times, cp-1 selected
runner and installer were captured in `/tmp/picker-recovery-before.txt`.
No activation has occurred at this preparation stage.


CI caught the older recovery contract's exact two-unit/host-closure pin. The
updated contract now first applies the same development module to its repaired
baseline and asserts exactly three restart-trigger unit changes plus the wrapper service
adding the standard root:utmp setgid-only utempter helper, then keeps
the original exact two-unit cp-1 delta. All guest, sibling, secret-file and
boot-counting assertions remain. The candidate host pin is `9rni5ln…`, obtained
from the evaluated build artifact rather than the live machine.

Builder cache lookup stalled with remote substitution enabled. Only this task's
three build/preview clients were interrupted; the retry keeps compilation on
Orion but supplies inputs from the local public cache (`builders-use-substitutes
false`). No builder configuration was edited. The voice config and original
symlink were backed up under
`~/.local/state/homelab-activation/picker-20261122T152948Z/`; the active link has
not yet been replaced.


## Activation and live listing regression — 2026-11-22

PR #512 merged as `ce608289` after all CI checks and exact-head approval.
Owner recipes activated recovery host `9rni5ln…` and Endeavour `i0wh4ya…`.
Home Manager is active, Hyprland reports no config errors, and both terminal
bindings are loaded. All six Kepler VM PIDs/start times and its boot ID stayed
unchanged; the cp-1 runner and installer hash are unchanged. Generation 142 is
the exact counter-free default, with no EFI selection override present.
No reboot was performed. Both versions of the temporary voice configuration
were backed up under the previously recorded backup directory; the latest
version used Super+I, Super+Shift+I and Super+Ctrl+I. Those voice bindings are
paused by the authorized managed-config activation. The voice worktree was
not modified. All three configured credential paths remain readable without
printing their contents.

A live PTY created `picker-smoke-20261122` in the homelab compute directory and
detached successfully, but reopening the picker did not show it. The list-only
`LC_ALL=C` caused tmux to replace tab delimiters with underscores; mocked lists
and the earlier PTY proof did not catch this later locale regression. A new
real-server test failed because the picker contained only New session. Using
`C.UTF-8` preserves delimiters and English missing-server diagnostics; all 13
picker tests pass. Independent review found no blocking issues and verified
missing-server handling. The fix changes no session-creation locale or deletion
semantics. The follow-up must pass CI/review and be deployed before resume/delete
can be reported as working live. The disposable smoke session remains for that
verification; existing user sessions are not cleanup targets.


CR found that the picker CI step did not provide tmux, allowing both real-server
tests to skip on runners without it. The workflow now builds the same tmux
package as the adjacent workspace smoke step and adds it to PATH for the picker
suite. This verified finding is fixed rather than waived; CI must execute all
13 picker tests. The production closure is unchanged by this workflow repair.


## TTY passthrough and dev tool set — 2026-11-22

`sk <arguments>` now passes `-o RequestTTY=yes` to SSH only when both standard
input and standard output are terminals, so full-screen commands receive a TTY
without changing redirected output. Before this, `sk btop` failed with
`ERROR: Failed to get size of terminal!`. The 7 focused launcher tests and the
full 39-test workspace suite pass, and a live local PTY rendered `btop` through
`sk`. Endeavour's Home Manager activation is active.

Ordinary Kepler imports the new `kepler-devtools` module: the existing
`dev-python`, `dev-javascript`, `dev-go`, `dev-java`, `dev-dotnet`, `dev-paths`
and `dev-nix-ld` modules, plus nvim, codex, opencode, claude-code, goose, herdr,
tuicr, hermes-agent, pi and deepseek-harness in Home Manager. It imports
`opencode-client` and `hermes-client`, so the agent CLIs receive the same
`/run/secrets/opencode/*` and Hermes client keys as Endeavour. The three added
harnesses land after the 2026-11-22 activation and are not part of that
evidence; `dsh-tui` also requires the user's secretspec keyring setup. The recovery host
keeps the smaller shared `kepler-development` module. Activation returned with no failed units, both ZFS
pools online, all six MicroVMs running, and the new toolchain on PATH.

The unreachable interval during rollout was not caused by this switch.
`journalctl -b -1` records `sudo ... systemctl reboot` at 17:16:56, shutdown
completion at 17:21:27, and the next boot at 17:29. The host returned on the
same new generation with Home Manager active; no separate tracking issue is
needed for the switch itself.

## Kepler ol/ow backends — 2026-11-23

Kepler imports the shared `desktop-workspaces` backend with its graphical
windows disabled. `ol` and `ow` point at the two local three-level OpenCode
servers, rooted at `/fast/compute/erik/Documents/erik/homelab` and
`/fast/compute/erik/Documents/nstech/dataplatform`. Only the two backend
services are enabled; desktop tmux and window units are not started. Live
activation and provider request checks remain pending.
