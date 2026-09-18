# Fleet capability composition

**Status:** Proposed — repository-grounded `/pl` and `/ip` draft; behavior contract unautomated; implementation and deployment not started.

## Human seed and destination

The operator requested: “merge 312 and lets prepare a seccond pr for standarization. Check other parts of the stack that could benefit from it. We can try to better use inheritance and composition here. Lets ground on repo ethos and files, then run a /pl and /ip”.

PR [#312](https://github.com/ErikBPF/desktop-nixos/pull/312) merged at `85401f6916304f0d87dd8cb1bba987bd9fd6c227`, the source baseline for this proposal. This PR prepares the design and delivery plan, not production configuration. The recommended first implementation preserves behavior. Network-manager migration is a separate, undecided proposal outside this implementation scope.

Destination: an operator can find each shared policy in one named capability and see its adoption in host/profile imports, while the evaluated host configurations retain their existing networking, access, hardware, workload and recovery behavior. “Inheritance” means Nix module composition and explicit option merging, not a new host-class hierarchy.

The [behavior contract](../behaviors/fleet-capability-composition/composition.feature) records proposed observable invariants. Its scenarios are not automated tests yet. Implementation requires acceptance of this bounded contract and the slice test set; this document does not claim that approval has happened.

## Repository grounding

The authoritative rules are [AGENTS.md](../../AGENTS.md), the [dendritic contract](../reference/dendritic-contract.md), and runnable [recipes](../../justfile). The [June structure proposal](../implemented/2026-06-24-repo-structure-improvements.md) already supports explicit composition and host anatomy; its remaining directory-reorganization phases are not prerequisites or silently revived here.

| Rule | Consequence for this effort |
|---|---|
| Auto-imported files are flake-parts modules; named leaves register in `flake.modules` | Preserve [registration](../../modules/configurations.nix) and [import-tree discovery](../../flake.nix). No aggregator tree or `specialArgs`. |
| Profiles compose; hosts keep identity and real exceptions | Extract demonstrably repeated capabilities. Do not move every host setting merely to make files symmetrical. |
| Shared facts have one owner | Read IP/MAC from [fleet metadata](../../modules/meta.nix); keep DHCP, DNS and ACL ownership in homelab-iac. Do not expand the published fleet schema for internal module wiring. |
| Minimal, opinionated implementation | Reuse native NixOS options and module merging. New options must serve current consumers; no backend plugin framework or universal host constructor. |
| Verify evaluated results and deploy through recipes | Preserve definition priorities, ordered lists and device naming. File movement or successful evaluation alone is not behavioral equivalence. |

No Graphify cache exists in this planning checkout. Grounding used targeted source reads. Local `just structure-check` passes; its size warnings are advisory. It does **not** enforce the documented prohibition on inline feature settings in profiles. `just docs-check` also passes at the baseline.

### Actual network differences

These are evaluated **source** facts at the baseline, not a claim that every merged change is deployed. Read-only NIC checks found magic-packet support on all four hosts; Apollo's shutdown/WoL cycle was verified in the preceding session. Kepler, Orion and Discovery have no recorded end-to-end power-cycle validation here.

| Host | Evaluated owner | Physical NIC / current link rule | WoL intent and preserved exception |
|---|---|---|---|
| Apollo | systemd-networkd | `lan0`, `10-apollo-lan` | `magic`; explicit MAC-based rename, DHCP and NAT refer to `lan0`. |
| Kepler | systemd-networkd | `enp5s0`, `10-kepler-lan` | `magic`; default naming policies, LAN aliases, DNS and cluster NAT remain. |
| Orion | NetworkManager | `enp4s0`, NM `connection-orion-wol` | `64`/magic; physical-MAC-scoped connection default. Existing profile uses `default`; explicit profile overrides take precedence. |
| Discovery | scripted networking | physical `eno1` behind `br0`, `10-eno1-no-tso` | `magic`; retain naming and TSO/TCP6-TSO/GSO disables on the physical NIC. |

Sources: [Apollo](../../modules/hosts/apollo/networking.nix), [Kepler](../../modules/hosts/kepler/networking.nix), [Orion](../../modules/hosts/orion/networking.nix), [Discovery](../../modules/hosts/discovery/networking.nix). Discovery's “systemd-networkd style” comment is not the evaluated backend: `networkmanager.enable = false` and `useNetworkd = false`. Its `.link` file is applied by udev independently of the IP manager.

### Other stack opportunities

| Priority | Evidence | Proposed disposition |
|---|---|---|
| 1 — shared policy | WoL is repeated across four host modules; existing `.link` exceptions must survive | One opt-in `lan-wake` capability; two existing backend mechanisms, no manager migration. |
| 1 — repeated routing choice | Apollo, Kepler and Orion repeat `accept-dns=true`, `accept-routes=false`; [base Tailscale](../../modules/networking/tailscale.nix) accepts routes | One explicitly imported `tailscale-local-client` leaf for those three hosts. Keep Discovery's router and roaming/cloud behavior distinct. |
| 2 — exact common bundle | [desktop HM profile](../../modules/profiles/desktop.nix), [Orion](../../modules/hosts/orion/default.nix) and [Apollo](../../modules/hosts/apollo/default.nix) repeat seven CLI/editor leaves | Import-only `profile-dev-cli` in the Home Manager registry. Keep GUI extras, aliases, credentials and gateway choices at their current owners. |
| 2 — ethos mismatch | [profile-server](../../modules/profiles/server.nix) sets the kernel inline; [profile-oci-guest](../../modules/profiles/oci-guest.nix) implements boot/security policy inline | Move definitions into named feature leaves; preserve current profile names/importers and exact priorities. No kernel upgrade or cloud access change. |
| Follow-up — real operational pain | [builder/deploy recipes](../../justfile) distinguish target but default builders to LAN addresses; Apollo deployment needed an explicit tailnet transport workaround | Separate proposal for composable address selection shared by build/preview/deploy. Keep target exclusion and rollback semantics. Transport fallback is a behavior change, not folded into this refactor. |
| Follow-up — small derivation | Three [Compose host modules](../../modules/hosts/discovery/compose.nix) repeat the repo's host path; [orchestration](../../modules/server/orchestration.nix) already has `repoPath`, `composeDir` and socket options | Consider deriving the default directory from existing repoPath/hostname later. Keep stack order, Docker versus rootless Podman and runtime-secret mappings explicit. |
| Already composed | [Syncthing](../../modules/services/syncthing-fleet.nix) generates host modules from topology; [Alloy](../../modules/services/alloy.nix) supplies common behavior | Reuse these patterns where warranted. Do not add another fleet registry, force Alloy onto the 1 GB Pi, or rewrite working shared modules. |
| Already shared, residual differences justified | [Kepler](../../modules/hosts/kepler/k3s-cluster.nix) imports [_k3s-node.nix](../../modules/services/_k3s-node.nix) | Defer a common cluster factory. Subnets, worker counts, guest kernels, storage and recovery differ. A common node implementation already exists. (Apollo's own cluster was retired 2026-09-17, so Kepler is now the only owner of this pattern.) |
| Preserve explicit overrides | [power-desktop](../../modules/hardware/power-desktop.nix), Kepler's watchdog/recovery policy, Orion's GPU policy | Do not turn incident-derived hardware exceptions into universal defaults. |
| Already improved; stale instruction | [upgrade-health-check](../../modules/services/upgrade-health-check.nix) appends `extraCriticalUnits` to read-only SSH/Tailscale checks; AGENTS still warns about replacing the base list | Preserve source behavior. Update that specific instruction if the relevant slice touches the contract; no new health-check abstraction. |

## `/pl`: bounded party, decision map and grill

The party/map/grill skills were applied directly as bounded perspectives; no separate BMAD runner was used. This is analysis, not independent human approval.

**Round 1 exchange.** Operator: “A host's capabilities should be obvious, and shared policy should not require four edits.” Architect: “Then compose named leaves, not a giant server profile; `role=server` includes the Wi-Fi Pi and public cloud VMs.” Tester challenges the architect: “A common `.link` file can steal Discovery's first match or change Kepler's name; preserving `WakeOnLan` alone proves too little.” Architect response: “Merge into each existing target rule and retain its identity/offload fields.” Security reviewer challenges the operator's idea of one network profile: “Discovery advertises routes; cloud guests restrict SSH to the tailnet. Equal-looking files must not erase these boundaries.”

**Disagreement retained.** A single IP manager could reduce operational vocabulary, but source evidence does not establish that migrating Orion or Discovery is needed for shared WoL intent. Recommendation: preserve managers now and require a separate behavior contract for migration. A universal cluster factory likewise has no demonstrated benefit beyond the node sharing already present.

### Decision map

| Decision | State / basis | Consequence |
|---|---|---|
| Keep explicit dendritic composition and ownership | Settled repository constraint | Reusable leaves outside `hosts/`; profiles import named leaves; no `specialArgs`. |
| Preserve current behavior for initial implementation | Recommended scope, derived from refactor ethos; pending operator review | Source equivalence is a release gate; no manager, kernel, NIC, firewall, credential or workload migration. |
| Share WoL intent while retaining backend ownership | Proposed architecture | `lan-wake` is explicitly imported by four hosts only. No inference from fleet role or mere MAC presence. |
| Keep one effective link rule per physical NIC | Required reliability invariant | Existing rule names and naming/offload policy remain. Never add a competing earlier rule for Discovery. |
| Separate LAN-local Tailscale policy from router/roaming policy | Proposed architecture | Three-host opt-in leaf; base enrollment/tagging untouched. |
| Share only the seven already-common HM imports | Proposed architecture | CLI profile imports `claude-code`, `codex`, `opencode`, `nvim`, `herdr`, `tmux`, `tuicr`; membership and host extras preserved. |
| Move inline profile features without changing priorities | Proposed architecture | Profiles remain stable entry points; `kernel-server` and `oci-guest` own existing behavior. |
| Keep fleet artifact schema and sibling repos unchanged | Scope boundary | No homelab-iac apply, workload migration, or publish-and-pin bump required. |

Dependencies: behavior-contract acceptance precedes implementation; source baseline precedes every refactor comparison; shared-profile changes require checks of **all** importers, not only the four WoL hosts. Network delivery requires a reviewed preview and recovery access. No dependency requires moving the whole repository tree.

Deferred decisions: whether a manager migration has enough operational benefit to justify its recovery cost, and whether builder-address selection should be the next follow-up. Neither is part of these implementation slices.

Fog: deployed generations may differ from this source baseline; firmware wake support beyond advertised NIC capability is untested on three hosts; any future manager migration needs full connection/bridge/wait-online inventory. Runtime facts must be recaptured before rollout.

Out of scope: automatic backend migration, renaming other NICs to `lan0`, globally enabled WoL, class inheritance or a universal host factory, role-driven hardware capabilities, fleet-schema changes, package/kernel refreshes, storage changes, rootful/rootless conversion, replacing the VM factory, cosmetic directory moves, and automatic shutdown tests.

Frontier: review the bounded contract and slice test set below; then implement the smallest agreed slice. Other opportunities remain ranked findings, not silently added tasks.

**Grill round 1 findings and revisions:**

- Reject “one `.link` per feature”: first-match semantics require composition into the existing device rule. Also reject the idea that using `.link` implies networkd owns IP configuration.
- Reject “server means wired WoL”: Archinaut and OCI guests are counterexamples. Require explicit adoption and a non-null permanent MAC.
- Keep Orion under NetworkManager, and test generated NM configuration as well as evaluated Nix options. A numeric flag in an unevaluated source file is not proof of behavior; explicit connection overrides must remain documented.
- Do not weaken `mkForce`/`mkDefault`, change list order, or normalize route flags during extraction. Security and reachability depend on existing precedence.
- Expand the test matrix for profile changes to Archinaut and all three OCI guests. Keep pinned GPU/guest-kernel exceptions and boot-entry limits.
- Keep the test runner explicit: the repository mixes unittest and plain pytest-style functions. `unittest discover` does not execute the plain functions in `tests/apollo-host`.

**Round 2 recheck:** the proposed scope has no manager or security migration; all selected scenarios have a slice below. The manager-migration question remains a future decision. The proposed architecture remains subject to review before implementation.

## `/ip`: implementation plan for the proposed contract

This is a reviewable delivery plan, not completed TDD or an approval record. Stop before implementation if review changes the behavior contract. Use the existing unittest/Nix evaluation pattern in [GPU option tests](../../tests/gpu-exchange/test_options.py); bind new cases in a proposed `tests/fleet-composition/test_options.py`. Keep this one small module rather than introducing Cucumber or a new test framework.

### Test seams and coverage

| Seam | Catches | Misses / cost |
|---|---|---|
| `nix eval` projections through stdlib unittest | Final MAC/link/NM/routing/profile/kernel/access behavior and merging | Does not force NixOS assertions or prove NIC/firmware behavior; evaluate all impacted hosts once per suite. |
| Negative fixture evaluated through `config.system.build.toplevel.drvPath` | Required NixOS assertions and diagnostic failures without building or activating | A plain option projection can succeed with failed assertions. Check subprocess failure and the intended diagnostic; an unrelated evaluation error is not a pass. |
| Generated `.link` and NetworkManager configuration | Wrong INI keys, flags, competing rule targets, naming/offload loss | Does not establish profile precedence on a changed live machine. Read only these non-secret artifacts. |
| Existing structural checks plus one small ownership assertion | Duplicate registration, accidental placement, policy still copied at old owners | Structure is not behavioral proof; avoid snapshotting whole source files or treating line counts as correctness. |
| Pinned before/after projections and toplevel dry-build | Unintended changes, missing imports and assertions, definition-priority conflicts | Store paths may change from source references; explain differences, never normalize meaningful paths/priorities away. |
| Supervised machine checks after deployment | Actual rule selection, WoL `g`, routes, SSH, bridges/NAT, critical units | End-to-end wake needs separately authorized shutdown; run one host at a time. |

The flake exports 13 configurations, not only the ten deployed hosts: `orion-esp-installer` directly [imports Orion](../../modules/hosts/orion/esp-installer.nix), while [archinaut-base](../../modules/hosts/archinaut-base/default.nix) and [drtest](../../modules/hosts/drtest/default.nix) have separate compositions. S1–S3 therefore include the inherited installer in their evaluation/dry-build matrices; the other two recovery/test configurations remain negative controls. No installer image is run, flashed or activated by these checks. Re-enumerate `nix eval --json .#nixosConfigurations --apply builtins.attrNames` before implementation rather than freezing a deployed-host-only list.

For each slice, capture only relevant non-secret output at the pinned pre-slice commit, then compare the same projection with identical inputs after refactoring. Equality tests are expected to pass on the baseline; they are regression guards, **not** the RED signal. RED comes from the missing shared capability/ownership or a concrete negative contract, as stated below. An unbound `.feature` file never counts as a passing test.

### S1 — one shared wake capability (W1–W4, R1)

- **Observable result:** four hosts select shared magic-packet policy; each keeps its current physical NIC, manager and addressing. Other hosts gain no wake policy.
- **Owner / surfaces:** desktop-nixos networking; new registered `modules/networking/lan-wake.nix`, four host compositions and their networking leaves, the inherited Orion installer, one new test module and the existing Apollo tests. Reuse each existing `.link` entry, not a new parallel entry.
- **Minimum design:** explicit import enables the capability; read permanent MAC from existing fleet metadata. Use the effective `networkmanager.enable` to select the current NM mechanism; for non-NM consumers, require the existing link-entry name through one typed `modules.lanWake.linkName` setting. No second backend enum, policy-choice framework, generic NIC constructor or new fleet fields. Reject absent MAC or an unset non-NM link-target setting with a clear Nix assertion. Guard generated attribute names and MAC interpolation so invalid inputs reach that diagnostic instead of an unrelated null/string error; fixture tests must force the system toplevel. Use the actual host network name for fleet lookup, not the output name `orion-esp-installer`. Merge only shared wake/MAC intent; naming, bridge, address, NAT and offload fields stay at their existing owner. An explicit NM profile override is an operational precondition, not silently overwritten.
- **RED:** `python3 -m unittest discover -s tests/fleet-composition -p 'test_*.py'`; missing `lan-wake` registration/adoption and missing-MAC/target diagnostics fail. Baseline equality checks for existing hosts pass. Bind W1–W4 and the wake portion of R1, including unselected configurations and Discovery's single effective rule. A fixture deliberately setting `assertions = [{ assertion = false; message = "wake assertion probe"; }]` must fail the negative-test runner; this verifies that the harness enforces assertions.
- **GREEN:** extract only those shared settings; retain effective `10-apollo-lan`, `10-kepler-lan`, `10-eno1-no-tso`, and Orion's NM section/key/64 flag. Remove superseded wake policy from host leaves. The existing [Apollo source test](../../tests/apollo-host/test_apollo.py) requires the MAC-match statement inside `hosts/apollo/networking.nix`; replace that location assertion with the existing effective-MAC/early-boot checks in [Apollo NIC recovery tests](../../tests/apollo-nic-recovery/test_options.py). Keep its other meaningful assertions; do not retain duplicate policy just to satisfy the old location check.
- **Verify:** same test command plus `python3 -m unittest discover -s tests/apollo-nic-recovery`; inspect generated early-boot and system link files and NM configuration; `just lint && just fmt-check && just structure-check`; run the existing Apollo plain-function suite with `nix shell --inputs-from . nixpkgs#python3Packages.pytest -c pytest -q tests/apollo-host`; toplevel `nix build --dry-run` for Apollo, Kepler, Orion, Discovery and `orion-esp-installer`. Compare the installer's forced disk graph before/after without executing it. Confirm null-MAC cloud guests still evaluate without opting in.
- **Delivery / rollback:** depends only on accepted contract. Preview Apollo first, then each remaining deployed host individually with its documented deployment mode. The inherited installer is validation-only, never a deployment target for this refactor. Record current generation and boot ID before any activation. If behavior differs while reachable, revert the slice and redeploy the recorded known-good configuration. If connectivity is lost, rely on the configured deploy-rs rollback or pre-established console/recovery access; an unreachable host cannot receive an SSH redeploy. Do not start a networking rollout without that recovery path. No reboot or shutdown without renewed operational authorization. A later full wake test requires down transition, packet send, new boot ID and service recovery.

### S2 — LAN-local Tailscale composition (N1, R1)

- **Observable result:** Apollo, Kepler and Orion continue accepting DNS and rejecting imported routes from one explicitly shared policy owner. Discovery keeps its exact advertised `/32` list; roaming and OCI clients retain their baseline preferences.
- **Owner / surfaces:** new `modules/networking/tailscale-local-client.nix`, three host imports/network leaves, same effective-option tests. Keep enrollment and `tag:server` logic in the existing base Tailscale leaf.
- **RED:** shared-leaf adoption/ownership check fails; baseline route/role/enrollment projections pass. Negative case proves Discovery is not selected; R1 checks that the installer inherits Orion's unchanged route policy.
- **GREEN:** extract the repeated two flags with their existing `mkForce` semantics; do not rewrite base list-merging or add Discovery to this group. Do not force a redundant routing-mode override on Orion unless equivalence and necessity are demonstrated.
- **Verify:** unittest command above; equality of effective route flags, advertised routes, role/enrollment flags and firewall exposure across all ten deployed host configurations plus `orion-esp-installer`; lint/format/structure and dry-builds for the three deployed consumers and the inherited installer. Preserve unrelated firewall ports and ranges, not only the SSH port.
- **Delivery / rollback:** depends on the S1 test-harness setup as written; it has no runtime/data dependency on WoL. Preview exact flag changes before activation; source refactor should not change them. Fail/rollback on changed route acceptance, lost SSH or DNS. No tailnet ACL apply.

### S3 — shared Home Manager developer bundle (D1, R1)

- **Observable result:** the same seven existing tools are composed once for desktop-profile consumers, Orion and Apollo; package choices, aliases, credentials and GUI extras remain host-specific where they already are.
- **Owner / surfaces:** new `modules/profiles/dev-cli.nix` registers **only** `flake.modules.home.profile-dev-cli`; modify the HM desktop profile and the two host HM import lists. No NixOS profile import of Home Manager leaves.
- **RED:** common-profile registration and adoption check fails; before/after effective package/config/alias projections pass on the baseline; R1 covers inherited installer Home Manager output. Negative example: Kepler/OCI/Pi acquire no developer bundle merely through `profile-base` or `profile-server`.
- **GREEN:** replace the exact seven common imports with the composition-only profile. Leave Apollo's safe aliases, VS Code/Atuin/Grafatui/worklab additions, Orion's colors and Hyprland, and desktop GUI applications at their current owners.
- **Verify:** same unittest suite; compare relevant package output paths, shell aliases and generated non-secret tool configuration for every importer (currently Apollo, Orion, Endeavour, Pathfinder and `orion-esp-installer`). Lint/format/structure; dry-build those five configurations, without executing the installer. Do not emit credential files or environment values into snapshots.
- **Delivery / rollback:** depends on the shared test harness, with no runtime dependency on S1/S2. Preview Home Manager changes; reject unintended package/alias/config changes. Revert the import extraction if behavior differs. No workload restart is part of the contract.

### S4 — server profile composes kernel policy (P1)

- **Observable result:** `profile-server` contains composition only; all existing consumers retain exact effective host/guest kernels and hardware overrides.
- **Owner / surfaces:** move its existing kernel definition verbatim into a registered `kernel-server` feature under `modules/hardware/`; import it from the same server profile. Preserve its current priority; do not switch it to `mkDefault` as part of extraction.
- **RED:** focused profile-purity assertion fails on the existing inline `boot.kernelPackages`; baseline kernel/boot projections pass. Avoid a generic Nix parser or false claim that the current structure recipe enforces purity.
- **GREEN:** one leaf extraction, no package-input or host-import changes.
- **Verify:** shared unittest suite and `python3 -m unittest discover -s tests/gpu-exchange`; check all profile-server importers: Apollo, Kepler, Discovery, Archinaut, Voyager, Telstar and Vanguard. Include guest kernel image paths and boot constraints. Run lint/format/structure and seven-host toplevel dry-builds. Run existing plain-function regressions with `nix shell --inputs-from . nixpkgs#python3Packages.pytest -c pytest -q tests/apollo-host tests/dendritic-structure`; do not silently skip them through unittest. This reuses the existing pytest suites with a pinned tool, rather than adding a framework.
- **Delivery / rollback:** depends on the shared test harness; no deployment merely to demonstrate file placement. If later deployed, unchanged kernel versions/images are required and host-specific boot-only rules remain mandatory. Revert extraction on any effective difference.

### S5 — OCI profile composes its platform capability (P2)

- **Observable result:** `profile-oci-guest` becomes an import-only composition of the upstream qemu guest profile and a named `oci-guest` feature; Voyager, Telstar and Vanguard keep identical recovery and access behavior.
- **Owner / surfaces:** existing OCI profile; new reusable leaf under `modules/hardware/` owning the current virtio, serial-console, EFI fallback, SMART and tailnet-only SSH policy. Retain exact priorities and list order. Do not infer applicability from `role=server`.
- **RED:** focused profile-purity check fails on current inline policy; baseline security/boot projections pass. Negative case: no public SSH opening or changes to disk/ESP ownership.
- **GREEN:** move existing definitions without changing their values; leave per-host disks, ESP paths, architectures and limits untouched.
- **Verify:** unittest suite; `nix shell --inputs-from . nixpkgs#python3Packages.pytest -c pytest -q tests/public-host-ssh`; lint/format/structure; dry-build Voyager, Telstar and Vanguard for both represented architectures. Compare `openFirewall=false`, tailnet SSH port 2222, initrd drivers, GRUB fallback, serial console and EFI-variable policy.
- **Delivery / rollback:** depends on the shared test harness. If accepted for deployment, use the documented canary-first OCI flow and activation-only versus magic-rollback settings already selected in deploy-rs. Preserve serial-console recovery. Revert code on any broadened access or changed boot behavior.

### Shared delivery gates and plan grill

Each slice owns its assertions and removal of the superseded definition. Proposed acceptance runner: `python3 -m unittest discover -s tests/fleet-composition -p 'test_*.py'`. Runner and test files are **planned**, not added by this documentation PR. S1 creates this test module and wires its command into the existing CI test job. S2–S5 reuse that harness and therefore depend on S1 as written. To deliver one earlier, move only harness setup and that slice's own tests into it; do not run assertions for capabilities that have not landed. Run `just docs-check` when updating the plan/status. Run full-flake checks only in CI/the documented remote flow; do not introduce a local `nix flake check` shortcut.

**CodeHero perspectives:** security (no widened firewall/tailnet/credential access), reliability (rule selection, naming, bridge/NAT, recovery), architecture (explicit ownership and no redundant abstraction), tests (final output assertions plus a real RED seam), compatibility (priorities, list order, input pins and supported architectures), operations (preview, deploy modes, rollback, current-state capture). Performance review guards against installing heavy agents/tools on the Pi or adding expensive per-assertion evaluations. Accessibility is not applicable to this infrastructure refactor.

**Plan grill round 1:** early-boot and system link output must agree (the existing Apollo NIC recovery test already covers this). An equivalence-only test would already pass before extraction, so every slice now names an ownership/purity/negative-case RED separately. Shared profiles expand the consumer matrix beyond the initial four hosts, so S4/S5 list all importers. NM wake overrides are checked as live preconditions; a Nix default cannot override an explicit profile setting. Broad closures and pre-existing source/live drift are not silently treated as refactor changes: capture baseline, inspect preview and stop rollout when unrelated activation changes appear.

**Plan grill round 2:** W1–W4 map to S1; R1 is divided across S1–S3 for the inherited recovery configuration; N1 maps to S2; D1 to S3; P1 to S4; P2 to S5. Re-evaluating the same immutable input twice is not a separate regression scenario; compare the pinned pre-refactor result with the composed result instead. Hardware/manager changes remain outside these slices. No hidden sibling-repo apply or dependency upgrade is required. The implementation plan is ready for review; tests have not run RED/GREEN and no implementation slice is claimed complete.

## Current-source review — 2026-09-13

Reviewed against main `9dc115d0641ad54db836d686a60936f81db47b71`. All five extraction premises remain present: four independent wake declarations; three repeated forced local-client route flags; the same seven common Home Manager imports; inline server kernel policy; and inline OCI boot/access policy. The proposed shared leaves do not yet exist. This recheck is source inspection, not fresh fleet evaluation or live acceptance. Capture a new pinned evaluation baseline before each implementation slice.

The existing planning worktree contained uncommitted review corrections before this publication pass. Those corrections are retained after checking the Orion installer import, Apollo source-test location assumption, assertion-forcing seam and rollback requirements against current source. The original human quotation remains unchanged. Publishing this plan does not mark its proposed contract accepted or authorize runtime rollout.

## Completion evidence for this planning PR

- #312 merged; no fleet deployment requested or performed in this planning turn.
- Read source modules, consumers, tests and deployment/rollback recipes at the stated baseline.
- Evaluated manager/kernel/Tailscale/SSH projections for ten deployed host configurations; corrected the Discovery backend assumption.
- `just structure-check` and baseline documentation links pass; large-file warnings are not new findings to auto-fix.
- Party/map/BDD/grill and scenario-to-slice mapping are recorded here. Human acceptance of the contract remains pending; second PR contains documentation only.
