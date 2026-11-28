# Official Orion Flash Next: configuration delivery

**Stage / revision:** implementation and RV / 3
**Status:** RV complete; all required local checks pass; not deployed
**Owner / date:** desktop-nixos / 2026-11-28 UTC
**Basis:** [accepted behavior](behavior.md), [verification contract](test-contract.md), and [RV record](rv-one-pager.md)

## Outcome and why it matters

Desktop declares `strata-flash-next` as Orion's official user service and removes the retired `ai-models` stack from automatic startup. This gives the existing runtime a durable owner and prevents the stale `strata-chat` container from competing for port 8080 after future activations or boots.

During the earlier monitoring pass, the live official endpoint reported `status: ok`, `service: strata`, and `loaded: true`. That recovery followed the user's reboot and preceded deployment of this patch. It is an observation about the existing runtime, not evidence that this configuration was activated.

## Changes

The host-scoped module preserves the observed saved `q2_0-120k.json` profile, pinned ROCm image digest, GPU access, host networking, model mounts, memory-lock limit, parallelism, and top-logprobs setting. Its startup targets retain `default.target` and `pqnld-decisions.service`. Software and the saved profile under `/opt/models/strata` remain existing host artifacts; this change does not package or replace them.

Orion's Compose startup list and Servarr rollout inventory drop `ai-models`, preserving other workloads. Discovery's probe becomes `strata-flash-next-health-probe`, retaining `strata_chat_health` and its timestamp for Grafana compatibility. The official `/health` handler returns `status: ok` even when the model is unloaded. The probe therefore parses JSON and requires both the Strata service identity and `loaded: true`; transport errors, malformed responses, and unloaded models publish zero.

## Evidence and limits

The [durable RED record](evidence/red.md) covers the original three source assertions and the RV readiness regression. The latter executes the shipped shell check without network access and initially produced seven assertion failures. All 22 focused tests now pass, including ten executable readiness cases; CI includes the new test directory.

After the readiness correction, lint, formatting, documentation links, and both `just dry orion` and `just dry discovery` passed again. The RV record lists exact validation commands. Dry-builds establish configuration validity and a build plan; they do not realize a closure or prove activation or inference quality. The optional structure checker reports an existing unrelated duplicate-name finding around `kepler-development`.

Independent review fixed the readiness false positive and clarified the delivery record. Earlier implementation review also completed CI test discovery and made retirement explicitly stop the stale container between crash-loop attempts. Operator-local first-draft patches remain scratch receipts; published review evidence lives in this directory.

## Activation and recovery

Run `just retire-orion-ai-models` **before the first Orion switch**, while the old unit still exists. It stops that Compose unit, explicitly stops `strata-chat`, and verifies it is no longer running. It preserves containers, bind mounts, model files, and sessions.

Use the established `just switch-orion` and `just switch-discovery` entry points. Home Manager's `backupFileExtension = "backup"` preserves the existing unmanaged service file; reconcile any pre-existing `.backup` collision without deleting the backup. Because orchestration sets `systemd.user.startServices = false`, run `just restart-orion-flash-next` after switching. Verify the unit resolves into `/nix/store`, the renamed probe timer is active, the tailnet endpoint reports a loaded Strata model, and the gauge becomes 1.

Deployment remains separate. A reviewed configuration reversal can undo these declarations; keep the retired stack stopped while diagnosing Flash Next to avoid restoring its port conflict. No runtime data is deleted by this patch.
