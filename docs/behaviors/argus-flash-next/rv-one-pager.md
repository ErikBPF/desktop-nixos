# Official Orion Flash Next: RV

**Stage / revision:** RV / 1
**Status:** complete; all required local gates pass; not deployed
**Owner / date:** desktop-nixos / 2026-11-28 UTC
**Basis:** [human seed](behavior.md) and [accepted verification contract](test-contract.md)

## Outcome and why it matters

Independent review found a readiness false positive in the Discovery probe. The official server returns HTTP 200 and `status: ok` while exposing model readiness separately through `loaded`. The original substring check could clear an outage alert before the model was ready. The repaired check requires a successful response containing the Strata service identity and a loaded model while preserving the existing Grafana metric names.

The scope remains the accepted Desktop configuration update: declare the observed official Flash Next service, retire stale automatic startup, and monitor the intended runtime. The human seed and corrections remain verbatim in `behavior.md`. PR publication is authorized by the user's subsequent “do a /rv then create a pr”; merge and deployment are separate.

## Independent passes and dispositions

Conformance checked the seed, contract, repository ownership, preservation of calibration, and activation boundaries. Correctness, adversarial, and simplicity passes traced Home Manager activation, existing Compose stop behavior, exact-target retirement, and caller reach. CodeHero covered security, reliability, operations, compatibility, architecture, performance, and tests. Accessibility is not applicable to this infrastructure-only change. Editorial review assessed structure before prose.

| Finding | Verified evidence | Disposition |
|---|---|---|
| Unloaded runtime incorrectly publishes healthy | Primary server source returns `status: ok` with `loaded: false`; independent execution reproduced gauge 1 | Fixed: curl must succeed and parsed JSON must contain `status: ok`, `service: strata`, and `loaded: true` |
| Opening contradicts observed live recovery | Delivery record said retirement was necessary before claiming health, then documented health before deployment | Fixed: outcome now describes durable ownership and preventing future conflicts; observed recovery is explicitly separate |
| Draft evidence is inaccessible to PR readers | Delivery record pointed to an operator-local `/tmp` patch | Fixed: local patches are labeled scratch; durable RED and RV records are included in the PR |

No additional verified security, lifecycle, compatibility, or simplicity defect was found. A possible clean-stop exit-status concern was discarded as unproven and unchanged from the accepted manual service. No acceptance criterion was removed to make checks pass.

## Evidence and limits

[RED evidence](evidence/red.md) records seven assertion failures before the readiness fix. Ten executable probe cases cover loaded/unloaded responses, incorrect service, missing/nonboolean readiness, malformed JSON, arrays, and transport errors. Together with source and monitoring checks, the focused suite passes 22 tests. Fixtures execute the shipped check with a local curl substitute; they perform no inference or network requests.

Final validation passed: `pytest -q --import-mode=importlib tests/orion-flash-next tests/monitoring-hardening` (22 passed), `just lint`, `just fmt-check`, `just docs-check`, `git diff HEAD --check`, `just dry orion`, and `just dry discovery`. Independent follow-up reran the ten readiness cases and confirmed the defect is closed. Three verified findings are fixed; zero verified findings or required local gates remain open, one unsupported hypothesis was discarded, and no required check was abandoned. Full flake checks belong in CI; no local `nix flake check` was run. The existing optional structure-check finding remains outside this patch.

## Continuing work and recovery

The reviewed branch is ready for the authorized commit, push, and pull request. Deployment uses the [ordered cutover](one-pager.md#activation-and-recovery): stop the old stack before switching, preserve Home Manager's backup, then explicitly reload/restart the official user service. Dry-build success does not establish activation, and the earlier live recovery is not attributed to undeployed changes. Model/profile files remain mutable host artifacts, preserved by this patch. Reverting source requires a reviewed activation; automatically resurrecting the retired stack would reintroduce its port conflict.
