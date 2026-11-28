# Voice dictation PR #517 merge review

**Stage / revision:** RV / 4, keymap feedback reconciliation
**Status:** Obsolete panel shortcuts retired across all desktops. Existing push authorization applies; fresh checks must precede merge.
**Owner / date:** desktop-nixos / 2026-11-28

## Outcome and accepted intent

Human seed, preserved verbatim: “lets analyse https://github.com/ErikBPF/desktop-nixos/pull/517 and prepare ir to merge”. Review preserves the accepted [gateway-first clipboard behavior](litellm-one-pager.md): Endeavour dictation, contextual composition, local fallback, cancellation, private-audio cleanup and no automatic paste. Personal microphone accuracy and universal gateway content exclusion remain unqualified.

The user clarified shortcut scope verbatim: “older keymaps are not desired. We can fully remove them”. Super+I/network and Super+U/monitors are intentionally retired everywhere. Endeavour alone receives Super+U/plain dictation, Super+I/context dictation and Super+Ctrl+I/cancel. Pathfinder, Orion and Challenger have no bindings for those three combinations.

## Review disposition and changes

The frozen first draft was PR head `4e508daece35d2445dcdfca0167f5b7fc9640f30`. Its [CI run](https://github.com/ErikBPF/desktop-nixos/actions/runs/45863136563) passed, and the [bot review](https://github.com/ErikBPF/desktop-nixos/pull/517#pullrequestreview-6078052669) approved that head. It was eight commits behind main `f173533a1039c15e1f0183fadaf5dee828c74ad1`. Conflict-free integration commit `7653f2a4` includes those upstream changes; the canonical checkout's unrelated work was preserved.

Initial independent review treated removing panel shortcuts on other desktops as an unintended compatibility change. Conditional restoration was added and published in `7653f2a4`. The user's clarification establishes global retirement as accepted behavior, so that compatibility finding is withdrawn and its preservation logic is removed. The earlier assessment and RED/GREEN evidence remain in that commit's history. No compatibility option or replacement panel mapping is needed.

The [evaluated shortcut tests](../../../tests/voice-dictation/test_bindings.py) now require global retirement and unique Endeavour voice actions. Existing CI already includes the entire voice test directory. This reconciliation changes no controller, gateway, credential, model or deployment behavior.

## Evidence and limits

- Earlier preparation: 36 voice/hygiene tests and independent review passed at `7653f2a4`. Its [fresh CI run](https://github.com/ErikBPF/desktop-nixos/actions/runs/46147088872) passed contracts, tooling, k3s smoke and all seven host evaluations. Bot review was pending when the shortcut contract changed; that head's checks do not qualify the revised head.
- Revised RED: the retirement test failed for Pathfinder, Orion and Challenger, each with two restored panel bindings where an empty list was required. Endeavour's three unique voice actions already passed. These were assertion failures, not infrastructure failures.
- Revised GREEN: all 36 voice/hygiene tests passed. Independent reviewer `voice_review` approved the removal and revised contract without additional findings. Final lint, formatting, documentation links and whitespace checks passed.
- Revised `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run --offline` exited zero for Endeavour, Pathfinder, Orion and Challenger. Logs: `/tmp/desktop-nixos-pr517-20261128/retired-keymaps-dry-<host>.log`. Offline dry-runs establish evaluation and planning, not successful fetching, builds or activation.

Independent security, reliability, performance, architecture, operations and test review found no additional verified production issue. TLS defaults, credential redirects, proxy bypass, bounded recording, fallback and clipboard failure boundaries were reviewed in source. None of those checks establishes physical microphone quality or backend content exclusion.

## Publication, remaining gates and recovery

[Desktop dependency #516](https://github.com/ErikBPF/desktop-nixos/pull/516), [IaC #180](https://github.com/ErikBPF/homelab-iac/pull/180), and [Servarr #363](https://github.com/ErikBPF/servarr/pull/363) are merged. This deployment repository has no published release; comparison uses maintained main. Global panel-shortcut retirement and Endeavour's new voice mappings are intentional changes from that configuration.

User answered “push” to native question `pr517-publish-20261128`, authorizing commits, pushes, description updates and fresh CI/review verification. This later keymap correction steers that same work. Checkout: `worktrees/voice-dictation`, branch `feat/voice-dictation`; publication authorization was recorded against RV/2. No further behavior question is pending.

Branch protection requires an up-to-date branch, required checks and resolved conversations. The ruleset also requires `hackerman-cr/evaluation` on the revised head. No PR merge or deployment is authorized by this preparation.

Physical microphone qualification, complete-generation activation, gateway logging observation and remote rewrite availability remain runtime follow-up. Recovery targets are retained in the [migration record](litellm-one-pager.md). This reconciliation changes no running service, clipboard, microphone or credential.
