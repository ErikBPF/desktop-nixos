# OpenCode runtime recovery and roaming builders

**Status:** PR #375 merged externally; Q-14 candidate built/reviewed and Q-16 Hermes scope accepted; GitGuardian false positive verified and app uninstalled by user. Synced through #385; local/dry gates pass; refreshed realized review and Endeavour switch pending.
**Stage / revision:** Post-merge source/status sync / 9, 2026-10-18.

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
including GitGuardian; those checks cover that historical head only.
RTK's separate guarded-backup/order regressions and native runtime
receipts are in the [migration record](../opencode-v2-migration/one-pager.md).
Earlier builder preflight authenticated to both former tailnet Nix stores;
this proves reachability/authentication, not successful workload offload.

Build attempt 1 timed out during closure transfer; attempt 2 failed with
`Broken pipe` transferring system units to Orion. Attempt 3 succeeded for
fb366a26, producing system 6g4br71zw2kkrq7f06bnsc88mwd1iap5. That older
candidate does not cover #380 or subsequent main. Q-14's single additional
thirty-minute build succeeded for ddd8d0df, producing system
80ikxlkix5dmmb5gywzw5h9y9fp6swl9 and HM 7drcpc1d1ivzv7kg9gxmy25p2nxm35gd.
That build allowance is consumed; no further build or retry is implied.
Main through cebf11d0 also carries #378's signed-cache receipt and #379's Hermes
source; preserving merged source does not activate Discovery or other hosts.

For fb366a26, lint/format/docs and Endeavour dry gates passed; 72 focused checks passed.
Initial combined pytest collection hit duplicate test-module names; the owning
separate suites avoid that runner error. Header smoke initially captured an
unintended compaction POST after its 10k synthetic context overflowed the tool
catalog. Matching the existing 100k roundtrip fixture restored all ten profile
checks without changing header/marker assertions or production configuration.
This does not prove Ponytail injection during compaction.

For ddd8d0df, lint/format/docs/fleet, Endeavour dry and 131 focused checks passed
(86 builder/tooling/work-profile, 29 workspace, ten profiles, five project and
one roaming). Head CI finished with ten successes, one skipped notification and
one GitGuardian failure. PR #375 merged externally as 80dafc8a; its tree exactly
matches the built candidate. These results are not fresh validation of later main.

Independent realized review confirmed approved builders/RTK and unchanged kernel
7.2.6/systemd 261.2. It also found Endeavour's inherited Hermes CLI/dependency
replacement: package metadata 0.21.3 to 0.0.0 despite pinned upstream v0.21.7,
and Hermes Python 3.13.15 to 3.14.7. Q-16 explicitly accepts this local runtime
scope; runtime compatibility remains untested. No new or removed service was found.

GitGuardian incident 38245533/occurrence 304898809 points to
`scripts/hermes-state-backup.sh:357`, a temporary-file size check, not a secret.
Full-script review verified the false positive; the same script was flagged in
PR #379. User uninstalled the external app. Residual checks found no operational
workflow, required context, webhook or IaC attachment in the inspected owners.
Gitleaks, ripsecrets and native secret scanning/push protection remain intact;
historical failed check records are retained, not rewritten as successes.

This branch now includes main through 6272d133: #382 retains guest KACE and
removes the obsolete uninstall path; #383 changes Apollo supervision only;
#384 isolates publisher-secret capture; #385 permits editing `.env.example`
templates while retaining runtime-secret denials. No capture helper or host
activation was run here. The last observed running/booted Endeavour system
remains x7vf18qsd08slr05amqvpakb016y8ldj, not the reviewed candidate.
Refresh candidate identity, dry checks, scope and preservation baseline before
any future switch; no live new-pool RPC or combined-generation behavior is claimed.

The sync through #385 passes lint/format/docs and 61 focused checks: 45
build-process/work-profile, 11 isolated publisher-capture and five project-policy
tests. Publisher tests intercept Sops/HTTP with fixtures; no real capture ran.
Endeavour and Apollo owner dry gates also pass. Existing rofi rename warnings,
ignored busy eval-cache warning and temporary-directory ResourceWarnings remain;
no unrelated repair was attempted. These checks do not realize or activate the
synced candidate.

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
