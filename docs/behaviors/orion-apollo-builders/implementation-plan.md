# Builder placement and guest-only KACE — delivery plan

**Status:** Builder source merged in PR #380; guest-only KACE correction in progress.

## Constraints and decisions

[Human seed](behavior.md) and [scenarios](behavior.feature) govern delivery. The
final plan grill supersedes the draft's zero-local assumption: ordinary Nix
derivations attempt remote hooks first; one local job is available when eligible
remote capacity is unavailable, including busy or incompatible builders.
`preferLocalBuild` remains native behavior. Failure after remote acceptance is
not an automatic local retry. `fallback` is a substitution setting, not a remote
retry switch. Do not add a scheduler or reachability framework.

Orion remains the signed cache. Apollo registration is capped at six jobs; do
not advertise aarch64 on Apollo or currently unobserved KVM on Orion. Native SSH
aliases select LAN by local network and Tailscale otherwise, with authenticated
public pins and strict noninteractive checking. This does not guarantee LAN
health fallback; failed remote capacity can permit bounded local execution.
Untrusted RPC can reject unsigned inputs. Do not disable signature checks or
grant trusted-user authority silently to bypass that failure.

## Slices, ownership and gates

1. **Recipes — one writer owns `justfile` and recipe tests.** RED: existing pool
   lacks Apollo; nested overrides disappear; Endeavour batch is local-only.
   GREEN: exported environment-default specs, symmetric target exclusions,
   remote-first ordinary recipes with one fallback job, obsolete KACE-only
   recipe restrictions/watchdog actions removed. Preserve unrelated recipes.
   Verify distributed-builds/build-process/builder-preflight pytest plus update-safe
   unittest. Require zero exit; print `PASS: builder recipe contracts` afterward.
2. **Daemon/trust — module writer, after credential design review.** RED: daemon
   lacks Apollo and server opt-ins. GREEN: native restricted Nix SSH endpoint,
   per-consumer encrypted keys, verified host pins, symmetric target exclusions,
   one-job fallback on enrolled consumers. No plaintext key in git or chat.
   Credential generation and host activation require explicit authority. Verify
   evaluated pools, identity paths, permissions, restricted endpoint and job caps;
   targeted dry gates on every affected host. No local full-flake check.
3. **KACE — latest correction retains the guest agent.** The user subsequently
   clarified that the VM is the only machine that must keep KACE. This supersedes
   the former guest-removal slice. RED: guest deployment lacks ampagent/konea
   checks and still exposes an uninstall helper. GREEN: restore apt-package/service
   checks, delete the helper and recipe, preserve host retirement, WARP, Trend
   and VM. Run work-profile/work-vm source regressions; no live guest operation.
   Existing host module absence is already GREEN, not invented test-first evidence.
4. **RV and merge — parent owns artifacts, integration and CI.** Preserve RED
   output and first draft; independent reviewers read source, then reconcile and
   rewrite summary from observed outcome. Lint/fmt/docs and affected dry gates
   precede GREEN claim; CI provides full checks. Publish leaf source/credentials
   before dependent consumer activation. Record static and live evidence separately.

## Recovery and limits

Revert only this task's source through normal git review; never discard older
dirty recovery/migration work. No secret/key rotation, forced pushes, guest data
purges or silent remote edits. Activation uses documented recipes and reviewed
rollback gates. Stop after three repairs of one failure and report evidence.
Source merge is authorized; source tests are not proof of deployed credentials,
real remote execution or local fallback under outage. Guest uninstall is no longer
requested.

## October 15 continuation (historical; superseded for the guest below)

The user authorized continuation and explicitly waived KACE backups/extra
validations. This supersedes the earlier guest identity/absence-check machinery;
retain ordinary source tests and command exit status, not additional runtime gates.
Two distinct per-server Ed25519 credentials were generated, inserted through SOPS
stdin, and read back internally. Private plaintext files were deleted afterward;
only encrypted values and public keys remain. No recipient rotation or trusted-user
escalation occurred. Host activation and representative untrusted-RPC build evidence
remain separate from encrypted source enrollment.

## Latest boundary correction and delivery hold

The final October 15 clarification requires guest-only KACE and explicitly says
to merge source, then wait for the next Orion cache build. The prior failed
removal connection never ran apt; no runtime repair or further uninstall attempt
is needed. Restore only the guest source contract and remove obsolete removal
entry points. Keep Orion/Apollo policy, dedicated keys and host cleanup unchanged.
Do not manually trigger cache warming, build host closures or activate hosts.
