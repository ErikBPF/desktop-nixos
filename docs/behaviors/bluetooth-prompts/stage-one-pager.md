# Bluetooth pairing prompts

**Status:** Implemented in the task worktree; configuration checks passed; not deployed.
**Stage / revision:** Implementation and independent review / 2, 2026-11-18.
**Owner:** desktop-nixos; branch `docs/bluetooth-prompts`, based on `50cf330e`.

## Outcome and human seed

> lets also propose a improvement for bluetooth conections that require a prompt or a ok

Propose visible, actionable Bluetooth pairing and authorization dialogs on Endeavour. A request should identify the device and offer the input or confirmation BlueZ requires. Approval must remain a human action. The user subsequently accepted continuation; implementation is authorized, deployment remains pending. The earlier Wi-Fi deployment authorization does not extend to this change.

## Current evidence

[Bluetooth configuration](../../../modules/hardware/bluetooth.nix) already enables BlueZ and Blueman. [Hyprland startup](../../../modules/desktop/hyprland.nix) directly launches `blueman-applet`, before importing the graphical environment into systemd and D-Bus. Read-only inspection on Endeavour found one running applet and tray, while the supplied `blueman-applet.service` was inactive. This shows unmanaged startup, not an observed crash or missing agent.

Installed Blueman 2.4.6 implements PIN/passkey entry, confirmation and service authorization. Its notification factory chooses desktop notifications when the server supports actions; the live server advertises actions. Setting `org.blueman.general.notification-daemon = false` forces built-in dialogs. Current effective GSettings and an actual failing pairing request have not been captured, so hidden notification actions are a hypothesis, not a proven fault.

Sources: [Blueman notification selection](https://github.com/blueman-project/blueman/blob/2.4.6/blueman/gui/Notification.py), [Blueman agent](https://github.com/blueman-project/blueman/blob/2.4.6/blueman/main/applet/BluezAgent.py), and [BlueZ agent API](https://bluez.readthedocs.io/en/latest/agent-api/). Installed source was also inspected directly.

## Implemented approach and alternatives

The [Home Manager feature](../../../modules/desktop/bluetooth-prompts.nix) enables dialogs and supervises the existing applet through the graphical session, with restart on failure. Endeavour alone imports it. Hyprland skips its direct launch when Home Manager owns the applet; the matching XDG autostart entry is hidden. UWSM supplies the graphical environment. Packaged D-Bus activation targets the same service. No replacement agent or custom prompt daemon was added.

Alternative: keep notifications and improve action access. This is smaller but retains notification visibility and interaction dependencies. A replacement Bluetooth frontend adds packages and another agent lifecycle without evidence that Blueman cannot handle this request.

Tradeoff: the Blueman dialog setting affects its notification factory generally, not only approval requests. Routine Bluetooth messages may also become dialogs. Check this during a pilot before accepting the preference. Keep normal reconnections free of new authentication prompts unless BlueZ requests one.

## Proposed examples and decisions

- A numeric-comparison request displays the device and code with Confirm/Deny.
- A PIN/passkey request allows entry, or displays the code to type on the peripheral.
- Denial, closure, cancellation and timeout must never mean approval.
- Service authorization distinguishes one-time Accept from explicit persistent trust. Preserve existing trust unless the user deliberately changes it.
- One request receives one response; later legitimate requests remain actionable. Do not copy Wi-Fi's once-per-connection suppression into Bluetooth authentication.
- Logging in starts one supervised agent. Recovery after an applet failure restores future prompts; an interrupted pairing may need retrying.

The continuation accepts these examples as the intended behavior; they are not automated device tests. Scope defaults to Endeavour; discoverability, auto-trust, audio routing, file reception and fleet rollout are excluded.

## Evidence limits and next gate

No pairing, trust mutation, service restart or deployment was performed. A future real-device pilot must cover confirm, deny, PIN input, cancellation and trusted reconnect. A phone can cover comparison; keyboard PIN behavior needs suitable hardware. Lock-screen behavior also needs verification; never approve unattended.

The user accepted continuation after the dialog-first proposal and its broader notification tradeoff. Recovery after a future deployment would restore the previous preference and startup ownership through source and normal deployment recipes; existing pairings must be preserved.

## Accepted continuation and implementation plan

The user said “continue” after receiving this proposal. Proceed with Endeavour's dialog-first configuration and its disclosed notification tradeoff; deployment remains a separate action. Implement one vertical configuration slice: reuse Home Manager's Blueman service, add D-Bus ownership and bounded restart delay, disable the matching XDG autostart entry, and omit Hyprland's direct launch only when Home Manager owns the applet. UWSM already owns graphical-session startup and environment import. Other hosts retain their existing launch.

Verification: `python3 tests/bluetooth-prompts/check.py` evaluates the real Endeavour configuration and prints `PASS: Bluetooth dialogs and supervised session configuration` only after checking dialog preference, session dependencies, D-Bus ownership, restart policy and disabled XDG startup. Run it before changes for RED, then after changes for GREEN. Run `just lint`, `just fmt-check`, `just dry endeavour`, and `just docs-check`; compare another Hyprland host's evaluated startup to preserve its behavior. These checks cannot establish real-device pairing or lock-screen behavior. No custom agent, permanent trust changes or new dependencies are planned.


## Implementation evidence and rollout boundary

The evaluated regression check failed on the original dialog preference before production edits, then passed with the feature enabled. The implementation uses Home Manager's existing service, preserves the packaged D-Bus name, adds `Restart=on-failure` with a three-second delay, and hides the XDG autostart entry. Hyprland omits its direct launch only when that service is enabled. Lint, formatting, documentation links and whitespace checks passed. An evaluated Orion control returned `services.blueman-applet.enable = false`; the shared Hyprland guard therefore preserves its direct startup. The earlier full Orion startup projection was interrupted during a cache stall; its empty output is not behavioral evidence. Independent review found no verified blockers, independently reran the configuration test, and confirmed Home Manager provides `tray.target` and packaged D-Bus activation selects the same service.

Before a future activation, preserve the separately implemented, unmerged Wi-Fi captive-portal fix from `worktrees/wifi-captive-login`; this Bluetooth branch starts from main and must not accidentally replace that live feature. Also arrange a clean handoff from the currently unmanaged applet: it must release `org.blueman.Applet` before the managed service starts, or activate through a fresh login. Do not interrupt an active pairing. No device pairings, trust settings or running services were changed during this work.

Real-device prompts, applet crash recovery and lock-screen behavior remain untested. The dialog preference affects routine Blueman notifications as disclosed in the proposal. First-draft evidence is retained under `.gsd/evidence/bluetooth-prompts/`.

The normal dry-build stalled fetching an existing source from the Orion cache; a direct HTTP read timed out. A parallel diagnostic also hit the Nix evaluation-cache lock. Both were stopped. The final targeted toplevel dry-run uses `--option substituters https://cache.nixos.org --option connect-timeout 10` for that invocation only; no persistent cache policy changed.

Final gate: `nix build .#nixosConfigurations.endeavour.config.system.build.toplevel --dry-run --option substituters https://cache.nixos.org --option connect-timeout 10` exited zero. Existing Rofi and PipeWire deprecation warnings remain. This is successful evaluation and dry-run planning, not a built or activated system. The real-device pilot and activation are still pending.

## PR review reconciliation — revision 3

Review: [PR #480, head a688f010](https://github.com/ErikBPF/desktop-nixos/pull/480#issuecomment-6996082877). The verified P2 identified an unregistered regression script and missing assertions for the preserved non-Endeavour startup branch. CI independently failed repository hygiene with `bluetooth-prompts` as the unlisted test directory; the same hygiene failure was reproduced locally before this repair.

The Check workflow's lint job now executes `python3 tests/bluetooth-prompts/check.py`. The script additionally evaluates Orion and requires both disabled managed-applet ownership and the direct `blueman-applet` launch in its `hyprland.start` callback. This resolves both parts of the finding without changing production configuration or weakening the hygiene gate. The earlier assertion-failing RED for Endeavour remains recorded above.

Hygiene, lint, formatting and documentation checks passed after the repair. The expanded evaluated contract passed for both Endeavour and Orion, printing `PASS: Bluetooth dialogs, supervised session and Orion startup`. Local Orion cache access stalled again, so the rerun uses an invocation-only official-cache override; CI uses its normal cache configuration. Device validation and deployment remain outside this repair.
