# Captive portal: HTTP login correction

**Stage / revision:** Feedback reconciliation, GREEN and deployment / 4
**Status:** Corrected launcher active and selected for boot; real hotspot retest pending.
**Verified:** 2026-11-18.
**Owner:** desktop-nixos, branch `feat/wifi-captive-login`.
**Basis:** [Accepted behavior and verbatim regression](behavior.md), plus the user's “apply” and “continue” instructions.

## Outcome and why

Endeavour now opens captive login windows with a separate Brave runtime profile and automatic HTTPS upgrades disabled for that profile. The user reported that the previous window reached the HTTPS GNOME probe and displayed “NetworkManager is online” instead of the hotspot form. The old launcher already supplied HTTP. Normal Brave upgrading that navigation is consistent with the report, but no trace of the original failing session was captured.

The running system and persistent system profile both resolve to `/nix/store/9qza0zd7kkv2958xg2lmgyhyxahg9rq8-nixos-system-endeavour-26.11.20261115.5c3cda7`. System activation completed successfully. This establishes deployment and simulated portal behavior, not a successful login on the user's hotspot.

## Changes and decisions

The [launcher](../../../modules/desktop/captive-portal.nix) passes `--user-data-dir=%t/captive-portal/browser` and `--disable-features=BraveHttpsByDefault,HttpsUpgrades`. Isolation prevents the ordinary browser process from absorbing the launch while ignoring its flags. The fixed HTTP probe URL remains unchanged. Explicit HTTPS destinations retain TLS and certificate validation; sandboxing and the normal Brave profile remain unchanged.

The listener and once-per-connection policy are unchanged. Activated Wi-Fi connections qualify; NetworkManager owner plus activation path identify each connection. Repeated checks and listener restarts cannot open another window for that activation. Reconnecting allows another window. Browser launches retain their separate transient service, so listener restarts do not kill the browser. No firewall, VPN or DNS policy changed.

## Evidence and limits

- The configuration regression first failed because the isolated-profile flag was missing. All 11 [unit/configuration tests](../../../tests/captive-portal/test_browser_config.py) now pass, including the existing listener behavior tests.
- The [browser smoke test](../../../tests/captive-portal/browser_smoke.py), run with evaluated service JSON and pinned Brave, observed an HTTP probe, an HTTP redirect to a simulated login page and its JavaScript render callback. Neither destination received an HTTPS CONNECT. An explicit HTTPS control produced CONNECT, confirming detection; it does not reproduce the old normal-profile bug.
- Early smoke-driver attempts timed out or raced browser cleanup. These were harness failures, not assertion-failing production RED. The final driver uses a page callback and a disposable transient service for complete process cleanup.
- `just lint`, `just fmt-check`, `just docs-check`, `just dry endeavour` and diff checks passed. Independent review found no verified blockers and independently reran all 11 tests; it did not rerun the browser smoke or a real hotspot.
- `just home-switch endeavour`, `just build endeavour` and `just switch endeavour` succeeded using the supported four-job builder override. A slow existing VM-driver download was recovered through the official compressed cache artifact and signature-checked `nix copy`; cache policy was unchanged.
- Closure comparison reported no package changes. Home Manager activation reports success; the listener is enabled, active/running with zero restarts, and its live command contains the isolated-profile flags. NetworkManager checking is enabled and current connectivity is `full`. Existing custom secret aliases are readable by their owner after activation; values were not inspected.

## Continuing work and recovery

Reconnect to the captive Wi-Fi to exercise the next permitted automatic window. Real hotspot login and reboot execution remain untested. VPN routing and portals that allowlist the probe can still affect detection. Changes remain staged, unmerged and unpublished. Earlier discovery and stage evidence remain in `.gsd/evidence/captive-portal/`. Recovery is a source revert followed by the normal deployment recipe; no rollback was performed.
