# RV report: repository simplification plan

**Date:** 2026-10-31, revision 2 2026-11-01
**Scope:** PL proposal, behavior contract, IP plan, PL one-pager. Planning
artifacts only; no source, recipe, or host change.
**Method:** independent read of the artifacts against current source, with each
figure re-measured and each verification command executed on the pre-change tree.

## Verdict

The plan is internally consistent and executable. Ten defects were found and
fixed across two revisions; no finding changed the accepted policy (D-1 to D-3).
Ready to start S1.

## Passes

### Conformance

- Contract scenarios map to slices: S1 (hygiene), S2 (recipes), S3 (module),
  S4 (tests), S5 (docs), S6 (split). No scenario lacks an owner.
- Proposal M1 to M6 map to slices; M7 is explicitly out of scope.
- Non-goals are consistent with the keep list: DR drills, Kepler recovery,
  receipts, and the work VM are untouched.

### Correctness (figures re-measured at `d091d982`)

| Figure | Artifact said | Re-measured | Fixed |
|---|---|---|---|
| Recipe count | 375 | 374 (`just --summary`, `just --list`) | Yes |
| Justfile lines | 8,861 | 8,860 (`wc -l`) | Yes |
| Deleted recipes | 56 | 55 (28 SWAG + 16 AdGuard + 7 Docker + 2 ESP + 2 audits) | Yes |
| Deleted recipe lines | not stated | 1,211 → file lands at ~7,649 | Added |
| CI test directories | 39 | 38 plus one file target | Yes |
| Unwired test directories | 61 of 115 | 61 of 115 | No |
| `# Moved` stubs | 22 | 22 (18 proposals, 4 implemented) | No |
| Stateful helpers | 15 / 234,150 B | 15 / 234,150 B | No |
| Unreferenced asset | 819,500 B | 819,500 B | No |
| Static suites passing | 32 of 35 | 32 passed, 3 failed | No |

### Security and blast radius

- Deleting `discovery-stateful-stack-ops` removes host packages. Verified it is
  not called by any sibling repository, retained recipe, or unit.
- The only host-side side effect is removal of system packages, a never-enabled
  oneshot unit, and tmpfiles entries; no runtime state is deleted.
- No secret, credential, or path with credential content is touched.

### Simplification

- No new abstraction is introduced: one test file, one recipe, one CI step.
- The conditional justfile split is gated on a measurement, not performed by
  assumption.
- The 4,000-line gate is arbitrary but explicit and cheap to revise.

## Findings and fixes

| ID | Finding | Fix |
|---|---|---|
| F1 | Recipe/line/CI counts were copied from an earlier pass and off by one. | Re-measured with `just --summary`, `wc -l`, and a directory-existence filter. |
| F2 | Deletion count did not match the per-cluster breakdown (28+16+7+2+2 = 55). | Corrected in proposal, one-pager, and plan. |
| F3 | S3 would have failed evaluation: `modules/hosts/discovery/default.nix:36` imports `m.nixos.discovery-stateful-stack-ops`. | Added the import removal and an eval gate to S3. |
| F4 | S2's verification regex missed `discovery-swag-result`, `discovery-swag-amendment-metadata-diagnostic`, and `discovery-adguard-inventory-raw`, so it would pass with leftovers. | Replaced with a prefix rule plus an explicit six-name allowlist; ran the pipeline on the pre-change tree and confirmed it fails. |
| F5 | The 12 KB README target was unrealistic: about 120 rows at roughly 150 B already exceed it. | Raised to 20 KB (from 36 KB). |
| F6 | `just hygiene-check` was not wired into the local gate, so `just check` would not match CI. | Added the call to `just check` in S4. |
| F7 | The proposal implied module dead code might be a deletion category while the scan was still outstanding. | Ran the scan: 199 registered names, 0 unreferenced. Stated as a closed non-category. |

## Revision 2 findings (keep/rebuild audit)

| ID | Finding | Fix |
|---|---|---|
| F8 | The plan deleted the P3 test and script family but left the seven `p3-adguard-outage-*` / `p3-generic-dhcp-client` recipes that call them, so the deletion would have left recipes pointing at missing files. | Added M1b and S2 scope; retained `p3-dns-preflight` and `p3-dns-verify` because `recover-kepler-dns` calls them. |
| F9 | The first audit counted 54 test directories as "wired" because any reference counted, including docs and modules. Run by an actual gate: 40. Fourteen are docs-only, so 75 are unexecuted. | Corrected the proposal, plan, and one-pager; the hygiene assertion uses CI/justfile/`tests/MANUAL.md` only. |
| F10 | Treating "reference exists" as "keep" hid 20 one-off recipes with no gate, no runtime consumer, and no safety token. | Added M1c with a rebuild source per recipe; each deleted one-off names the doc or runbook that keeps its command. |

Three figures were re-measured after the P3 and one-off additions: 82 deleted
recipes, 1,976 deleted lines, 292 recipes and 6,884 lines remaining. The split
map sums to 6,861 attributed lines; the difference is blank and comment lines
between recipe spans.

## Residual risks

- The 32 static suites pass under the host Python; the dev-shell pytest
  environment is not identical. S4's CI run is the first proof there, and the
  120 s cap fails the slice if the set is slower than expected.
- The 18 manual directories are declared, not proven. Their commands are
  recorded but not executed by this change.
- `tests/harbor-version-reconcile` references a moved script path; S4 must
  repair or delete it rather than declare it manual unchanged.
- Worktree and branch cleanup (M7) is deferred and needs its own inspection.

## Not found

- No scenario in the contract is unowned or untestable.
- No deleted recipe is referenced by a retained recipe, script, module, or
  sibling repository.
- No acceptance evidence, `.feature` contract, or RV report is scheduled for
  deletion.
