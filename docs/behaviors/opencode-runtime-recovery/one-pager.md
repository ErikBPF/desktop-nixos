# OpenCode runtime recovery and roaming builders

**Status:** PR #375 published; Q-14 main-policy reconciliation and local gates pass; candidate build/CI/realized review and Endeavour switch pending. DNS/route mutation remains separate.
**Stage / revision:** RV policy reconciliation / 7, 2026-10-18.

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

The original recovery patch selected unconditional tailnet Orion/Kepler endpoints,
existing `accept-new` trust and disabled local jobs. Main #380 explicitly
superseded that unpublished policy. Q-14 accepts the replacement for this
Endeavour delivery; original seeds and RED/GREEN receipts remain historical.

The [main-owned builder record](../orion-apollo-builders/one-pager.md) now owns
Orion/Apollo aliases, fleet LAN/tailnet selection, strict authenticated public
pins, revised capacity/features and one local fallback job. Symmetric target
exclusion remains. Endeavour keeps its existing private SSH identity; new server
credential installation belongs to Kepler/Discovery, neither activated here.
No old builder implementation or assertions are restored over main. LAN selection
is not health failover, and static policy checks do not prove live RPC dispatch.

RTK retirement and its restart triggers remain this PR's independent source
change. Sudo wrapper-first PATH already exists on main. User activation alone
cannot converge system HM ownership; deployment uses `just switch endeavour`.
No DNS/ACL/route mutation or guest uninstall is selected by this integration.

## Evidence and repairs

Pre-reconciliation reviews covered conformance, correctness, security, operations,
adversarial failure paths and simplicity. Four assertion failures established
RED for recipe/daemon tailnet addresses, SSH matches and self-exclusion. Initial
synthetic fixture duplicated an already imported module; that setup error was
fixed before assertion RED and is not counted as behavioral evidence.

After minimal source repair, all 15 focused distributed-build/build-process/
preflight tests passed. These checks join existing pinned-Python CI, without
new dependencies. Combined lint/format/docs/fleet consistency and Endeavour dry
build pass, as do 29 workspace, 10 profile and five project tests. Fresh source
risk review found no new verified defect; prose review clarified historical
runtime/kernel receipts. Prior PR head fe3f63e passed all eleven CI checks,
including GitGuardian; refreshed-head CI, combined closure and post-switch
checks remain pending. RTK's separate guarded-backup/order regressions and native runtime
receipts are in the [migration record](../opencode-v2-migration/one-pager.md).
Earlier builder preflight authenticated to both former tailnet Nix stores;
this proves reachability/authentication, not successful workload offload.

Build attempt 1 timed out during closure transfer; attempt 2 failed with
`Broken pipe` transferring system units to Orion. Attempt 3 succeeded for
fb366a26, producing system 6g4br71zw2kkrq7f06bnsc88mwd1iap5. That older
candidate does not cover #380 or subsequent main. Q-14 authorizes one additional
thirty-minute build, no retries, for the reconciled latest-main candidate.
Main through cebf11d0 also carries #378's signed-cache receipt and #379's Hermes
source; preserving merged source does not activate Discovery or other hosts.

For fb366a26, lint/format/docs and Endeavour dry gates passed; 72 focused checks passed.
Initial combined pytest collection hit duplicate test-module names; the owning
separate suites avoid that runner error. Header smoke initially captured an
unintended compaction POST after its 10k synthetic context overflowed the tool
catalog. Matching the existing 100k roundtrip fixture restored all ten profile
checks without changing header/marker assertions or production configuration.
This does not prove Ponytail injection during compaction.

Current Q-14 reconciliation passes lint/format/docs/fleet and Endeavour dry;
131 focused checks pass (86 builder/tooling/work-profile, 29 workspace, ten
profiles, five project and one roaming). Independent review confirms main's
four conflicting files are byte-identical and only six intended PR paths
differ from main. Installed builder aliases are not active yet; the owner
recipe's accepted one-job fallback can bootstrap without temporary SSH edits.
No live new-pool RPC or new-generation behavior is claimed before activation.

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
Q-14 supersedes only the earlier builder-policy/budget boundary: preserve main's
Orion/Apollo policy, then require fresh CI and realized Endeavour scope review.
