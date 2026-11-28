# Voice dictation PR #517 merge review

**Stage / revision:** RV / 3, publication authorized
**Status:** Local code preparation is green. User authorized publication; fresh remote checks must precede merge.
**Owner / date:** desktop-nixos / 2026-11-28

## Outcome and why

Human seed, preserved verbatim: “lets analyse https://github.com/ErikBPF/desktop-nixos/pull/517 and prepare ir to merge”. Review preserves the accepted [gateway-first clipboard behavior](litellm-one-pager.md): Endeavour dictation, contextual composition, local fallback, cancellation, private-audio cleanup and no automatic paste. Personal microphone accuracy and universal gateway content exclusion remain unqualified.

The frozen first draft was PR head `4e508daece35d2445dcdfca0167f5b7fc9640f30`. Its [CI run](https://github.com/ErikBPF/desktop-nixos/actions/runs/45863136563) passed, and the [latest bot review](https://github.com/ErikBPF/desktop-nixos/pull/517#pullrequestreview-6078052669) approved that head. The PR was eight commits behind `main` at `f173533a1039c15e1f0183fadaf5dee828c74ad1`. A conflict-free local merge includes those upstream changes. The canonical checkout's unrelated work was preserved.

## Verified finding and changes

Independent review found one P2 compatibility regression: deleting Super+I/U from shared Hyprland removed network/monitor panel shortcuts on desktops without voice integration. Pathfinder, Orion and the newly merged Challenger all import that shared configuration; only Endeavour imports voice dictation.

The correction restores the original panel bindings only when the Home Manager voice service template is absent. This uses the existing feature declaration, avoiding hostname checks and another enable option. Endeavour retains exactly Super+U/plain, Super+I/context and Super+Ctrl+I/cancel. Other desktops retain their existing Super+I/network and Super+U/monitors actions.

The new [evaluated binding regression tests](../../../tests/voice-dictation/test_bindings.py) exercise the real four-host Nix configuration. Existing CI already includes the entire voice test directory. No controller, gateway, credential, model or deployment behavior changed during this review.

## Evidence and limits

- Baseline and current-main integration: `rtk pytest -q tests/voice-dictation tests/repository-hygiene` passed 34 tests before adding the regression.
- RED: the new binding test failed with `0 != 2` for each of Pathfinder, Orion and Challenger. Endeavour's uniqueness/action check already passed. These were assertion failures, not infrastructure failures.
- GREEN: the combined suite passed 36 tests after the four-line binding correction. Independent reviewer `voice_review` separately reran the two evaluated binding tests and approved the fix.
- Final `just lint`, `just fmt-check`, `just docs-check` and `git diff --cached --check` passed.
- Final `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run` exited zero for Endeavour, Pathfinder, Orion and Challenger. Orion cache requests timed out; Nix still produced the build plans. These results establish evaluation and planning, not successful artifact fetching, builds or activation. Logs remain locally under `/tmp/desktop-nixos-pr517-20261128/dry-<host>.log`.

The security, reliability, performance, architecture, compatibility, operations and test passes produced no additional verified production finding. Source review confirms explicit TLS verification defaults, refused credential redirects, proxy bypass, bounded recording, fallback and clipboard failure boundaries. These checks do not establish real microphone quality or backend logging behavior.

## Merge gates and recovery

[Desktop dependency #516](https://github.com/ErikBPF/desktop-nixos/pull/516), [IaC #180](https://github.com/ErikBPF/homelab-iac/pull/180), and [Servarr #363](https://github.com/ErikBPF/servarr/pull/363) are merged. No unresolved GitHub review threads exist. This deployment repository has no published release; comparison uses its maintained `main` configuration. Panel preservation is required compatibility behavior; the new Endeavour voice shortcuts are intentional.

Branch protection requires an up-to-date branch, all required checks and resolved conversations. The repository ruleset also requires `hackerman-cr/evaluation`. Existing green checks belong to the old head; publishing this update must obtain fresh CI and review before merge. User authorized committing and publishing the prepared branch and revised PR description. No PR merge or deployment is included.

Resolved native async question, local ID `pr517-publish-20261128`: user answered “push”, authorizing the prepared commit, push, PR-description update and fresh CI/review verification. Context: checkout `worktrees/voice-dictation`, branch `feat/voice-dictation`, artifact RV/2, reviewed original head `4e508da`. No tuicr session is active; independent review was performed by `voice_review`.

Physical microphone qualification, complete-generation activation, gateway logging observation and remote rewrite availability remain runtime follow-up. Existing recovery targets remain documented in the [migration record](litellm-one-pager.md). This preparation changes no running service, clipboard, microphone or credential.
