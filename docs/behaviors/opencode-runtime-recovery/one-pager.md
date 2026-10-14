# OpenCode runtime recovery and roaming builders

**Status:** combined local gates and independent review pass; publication and Endeavour switch pending. DNS/route approval remains separate.
**Stage / revision:** RV second draft / combined local GREEN / 5, 2026-10-14.

## Outcome and human seeds

Q-13 selects three streams for main delivery: guarded V1 RTK retirement,
roaming-builder recovery and sudo-PATH reconciliation. The integration lives
in a fresh worktree; original dirty checkouts remain untouched. Native V2
migration and status PRs #373/#374 were already merged. Sudo-PATH changes
already exist on main, so no older V1 workspace module is imported.

The selected recovery record supplied these human seeds verbatim:

- “weneed to fix sudo”; “continue. Also check why opencode credentials are broken”.
- “lets explore how to fix dns also”; “we need to use .210. SSH discovery and validate it and adguard”; “inspect and validate tailscale”.

That record is preserved in the original `endeavour-always-on` worktree and
scratch receipts. Its runtime/DNS observations below are historical, not tests
performed by this integration. The `.210` destination remains accepted; no
tailnet-only DNS/ingress redesign, route approval or Discovery repair is selected.

## Changes and rationale

Recipe builders use fleet-owned tailnet addresses instead of unreachable LAN
addresses when Endeavour roams. Review found that recipe overrides alone left
ordinary daemon builds LAN-only. The shared module now uses the same fleet
facts, preserving SSH user/key, port 2222, capacity, systems and features.
Both builder hosts exclude themselves when offload is enabled.

LAN and tailnet SSH matches retain `accept-new`: first contact uses existing
trust-on-first-use policy; changed keys remain rejected. A new address is a
new trust entry, not proof that prior LAN trust covers it. No private keys,
authorized keys, SSH permissions, ACLs or known-host files are changed by source
integration. Tests inspect policy text; they do not simulate changed-key rejection.

Normal build/switch recipes still disable local jobs. Builder availability is
required; local fallback policy is not silently expanded. Direct tailnet builder
access requires no Discovery subnet-route approval. User activation alone cannot
update boot's system HM ownership; deployment uses `just switch endeavour`.

## Evidence and repairs

Independent reviews covered conformance, correctness, security, operations,
adversarial failure paths and simplicity. Four assertion failures established
RED for recipe/daemon tailnet addresses, SSH matches and self-exclusion. Initial
synthetic fixture duplicated an already imported module; that setup error was
fixed before assertion RED and is not counted as behavioral evidence.

After minimal source repair, all 15 focused distributed-build/build-process/
preflight tests passed. These checks join existing pinned-Python CI, without
new dependencies. Combined lint/format/docs/fleet consistency and Endeavour dry
build pass, as do 29 workspace, 10 profile and five project tests. Fresh source
risk review found no new verified defect; prose review clarified historical
runtime/kernel receipts. CI, combined closure and post-switch checks remain
pending. RTK's separate guarded-backup/order regressions and native runtime
receipts are in the [migration record](../opencode-v2-migration/one-pager.md).
Owner builder preflight now authenticated to both declared tailnet Nix stores;
this proves reachability/authentication, not successful workload offload.

## Historical observations, limits and recovery

Recovery previously found an intact sudo wrapper but a controlling PATH that
selected unwrapped sudo. Wrapper-first PATH fixed that invocation without
permission changes. Existing processes retain inherited environments; preserved
tmux/panes are not silently restarted or rewritten.

Recovery's system switch installed native V2 HM successfully; no subsequent
reboot proved persistence. Value-free provider checks distinguished Work's
unsupported effort option from credential rejection. Home discovery worked
through tailnet while ordinary DNS still targeted unreachable `.210`; no paid
completion was run in that recovery. Its Discovery/AdGuard checks found healthy
listeners but advertised subnet routes lacked approval. Those observations do
not authorize networking mutations or establish current model/tool E2E.

Q-13 permits reviewed publication, normal squash merges and Endeavour-only
activation. No force-push, security bypass, cleanup, other-host activation,
reboot, rollback, credential rotation or DNS/route changes. Stop for unexpected
combined closure differences. Recover only through matching known system/user
generations after separate authorization; old V1 configuration recreates drift.
