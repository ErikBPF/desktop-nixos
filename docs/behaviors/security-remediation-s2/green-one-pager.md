# Apollo development controls: GREEN

**Stage / revision:** GREEN / 1. **Status:** source regression and Apollo
toplevel dry-run checks passed. **Owner / date:** desktop-nixos / 2026-11-07.
**Human seed, verbatim:** "do s0 to s4". Scope is S2 of the reviewed homelab
security-remediation plan: remove vLLM development controls while retaining the
existing inference recipe and its containment settings.

## Outcome and why it matters

The Nix-owned serving script now unsets `VLLM_SERVER_DEV_MODE` before starting
vLLM. The matching GitOps manual reference does the same. Explicitly unsetting
the variable protects the script from inheriting an enabled value from an image
or caller; deleting only the export would leave that path open.

This closes the declared development-mode switch in source. It does not prove
the image's exact package version, an unavailable development HTTP endpoint,
effective firewall policy or a deployed fix. No running service was contacted
or changed, and no shell command was sent to an inference engine.

## What changed

`modules/hosts/apollo/default.nix` replaces the enabled development export with
an unset, leaving the model, image ID, CUDA/GPU settings, LMCache connector,
context capacity, serving port and supervision unchanged. The service still
uses UID/GID `1000:100`, `no-new-privileges`, a read-only model/runtime mount and
the existing writable cache. The preflight still requires its expected chain,
source rules, storage, GPUs and pinned image.

The new `tests/apollo-host/test_ai_boundary.py` executes the embedded serving
shell with a fake vLLM binary and an intentionally inherited enabled variable.
It checks the resulting environment and intended model invocation, without
loading GPU software. A second source check preserves the existing container
and preflight boundaries. GitOps extends its existing `tests/apollo-launch.py`
with equivalent shell execution; the server and launch hardware are never used.

## Evidence and limits

| Check | Observed result |
|---|---|
| Initial fixture run | Environment failure resolving Bash from minimal PATH; corrected to resolved executable before counting RED |
| `pytest -q tests/apollo-host/test_ai_boundary.py` before the fix | Assertion RED: inherited development value was `1`; one failed, one passed |
| GitOps `python3 tests/apollo-launch.py` before the fix | Assertion RED: inherited development value was `1`; one failure in three tests |
| `pytest -q tests/apollo-host` after the fix | Nine passed |
| GitOps `python3 tests/apollo-launch.py` after the fix | Three passed |
| `just lint` and `just fmt-check` | Both passed |
| `nix build .#nixosConfigurations.apollo.config.system.build.toplevel --dry-run` | Passed, exit 0; evaluated derivations, no build or activation |

## Continuing work and recovery

Wire `tests/apollo-host` into desktop's existing static pytest CI step. The
manual launch documents that Tailscale's earlier INPUT chain can accept traffic
before the custom allowlist; these unchanged checks therefore do not establish
Discovery-only effective reachability. Reconcile that through the existing
network-hardening work and an explicitly authorized live acceptance window.

Before rollout, validate the evaluated Apollo configuration and harmless endpoint
presence from approved and denied vantages. Recovery must preserve the disabled
development boundary: stop serving or restore a known-good image/configuration
behind that boundary, rather than re-enable administrative development endpoints.
No image was rebuilt or replaced and no credential material was inspected.

## Published CI repair

The first PR run exposed a missing CI dependency: the bare pytest selection collected an existing Apollo recipe test that invokes `just`. Moved the Apollo directory to the existing `nix develop` pytest invocation. The exact flake-built Python with pytest and the development shell passed all nine Apollo tests. Lint and formatting passed. This corrects CI wiring without changing host behavior; the repaired PR head still needs its remote checks.
