# Orion/Apollo builders and KACE retirement

**Status:** Locally verified source; activation and guest removal pending.
**Stage:** GREEN and independent RV reconciled, 2026-10-15.

## Outcome and why

The [human seed](behavior.md) selects Orion/Apollo remote builders, permits local
fallback, enrolls Kepler/Discovery daemons, and retires KACE from Endeavour and its
Ubuntu guest while retaining the VM. Orion remains the official signed cache.
This supersedes the unpublished unconditional-Tailscale/Kepler recovery patch;
older recovery/migration worktrees remain untouched. Prior hardening/delivery
receipts are merged, not proof this new policy is activated.

October 15 continuation authorized credential preparation and waived KACE backups
and extra validations. Removal therefore uses one scoped package command.

## Changes and decisions

The [delivery plan](implementation-plan.md) separates recipe, daemon/trust, guest
and integration ownership. [Scenarios](behavior.feature) are documentary; tests
cover source and mocked behavior, not every runtime outcome.

Orion/Apollo replace the former pool with symmetric target exclusion. Exported
Just variables preserve nested overrides. Three consumers receive one local
fallback job. Native Nix tries remote hooks first for ordinary derivations;
busy, incompatible or connection-failing capacity can permit local execution.
`preferLocalBuild` remains an exception; failure after remote acceptance does not
automatically retry locally. Core settings guide builders, not hard CPU quotas.

Apollo is capped at six advertised jobs without aarch64; Orion retains aarch64
without currently unobserved KVM. Native SSH aliases select LAN by interface
network, Tailscale otherwise, with authenticated public pins and strict bounded
connections. This is not health failover: overlapping subnets can select an
unreachable LAN address. No custom scheduler is needed.

Distinct per-server Ed25519 keys were encrypted through SOPS stdin and internally
read back; handoff files were removed. Existing ciphertext and recipient envelope
were unchanged. Shared recipients provide host-specific runtime placement, not
cryptographic isolation. Restricted native `ssh-ng` RPC remains untrusted: no
admin shell or root-equivalent trusted-user grant. It is not read-only; unsigned
inputs can fail. Never silently disable signatures or escalate trust.

KACE requirements/watchdog actions and obsolete build-locality restrictions are
removed; WARP, Trend and VM remain. The helper removes only `ampagent`, retaining
configuration. Existing `modules/pre-commit.nix` owns generated hook configuration;
the declared development shell restores it, including secret scanning. A temporary
replacement was removed rather than introducing duplicate hook policy.

## Evidence and review

- Final integrated suites: **73 pytest and nine update-safe unittest cases pass**.
- Lint, format, docs, whitespace and native hooks (Alejandra, ripsecrets, Statix)
  pass. Composed dry gates
  pass for Endeavour, Kepler, Discovery, Orion and Apollo.
- Guest source RED: two assertion failures, then five passing tests. Host module
  absence was already GREEN, not invented RED.
- Recipe RV found Orion recovery graph target-exclusion and three single-builder
  x86-helper gaps: nine assertion failures preceded repairs, then passed.
- Independent conformance, correctness, security, operations, adversarial,
  simplicity and editorial reviews reconciled. Composed settings/effective SSH
  parsing were checked; permanent module tests remain isolated. Diagnostic
  preflight failure is not a mandatory functional-build gate.
- A disposable native Nix build attempted an unavailable loopback remote, then
  produced expected one-job local output. It does not prove fleet RPC dispatch or
  recovery after accepted remote compilation fails.

First drafts and RED/GREEN receipts remain in OpenCode's task-local evidence
folder, including `orion-apollo-native-fallback.json`. CI is the separate
publication gate, tracked by the implementation PR.

## Waiting work and recovery

Authorized `just --no-dotenv remove-ubuntu-work-kace` exited **255**:
`192.168.122.74 port 22: No route to host`. No package command ran; no backup,
extra guest validation or VM start followed. Retry when reachable.

Deploy builders before consumers; verify restricted RPC and secret installation
before claiming live enrollment. Preserve closure/unit-diff/rollback gates and
Kepler's supervised stability hold. Source publication is not activation or guest
uninstall. Revert only task source through normal review; preserve older work,
unrelated keys/data and immutable history. Stop after three repairs of one failure.
