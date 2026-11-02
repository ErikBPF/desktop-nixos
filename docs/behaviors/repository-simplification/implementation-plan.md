# Implementation plan: repository simplification

**Status:** Proposed — `/ip` complete; slices not started.
**Date:** 2026-10-31
**Contract:** [`repository-simplification.feature`](repository-simplification.feature)
**Proposal:** [`../../proposals/2026-10-31-repository-simplification.md`](../../proposals/2026-10-31-repository-simplification.md)
**Baseline:** `d091d982`

## Trace

- `justfile` is the single recipe source; CI calls `just lint`, `just fmt-check`,
  and per-directory Python/Node suites. There is no `just/` import today;
  `just` 1.58 supports `import`.
- `pytest` is already in the dev shell (`modules/dev/python.nix:11`), so a
  pytest-based static gate needs no new dependency.
- Static test directories resolve paths from `Path(__file__).parents[2]`, so
  they are cwd-independent and cheap.
- Discovery imports every `modules/` file through import-tree;
  `modules/hosts/discovery/stateful-stack-ops.nix` registers system packages, an
  unused oneshot unit, and tmpfiles rules.
- No sibling repository references the tooling being deleted (checked with
  `git grep` over `homelab-iac`, `homelab-gitops`, `servarr`, `aster`,
  `cognee-homelab`, `ndc`).

## Test verdict data (recorded here so S4 executes, not decides)

Unwired directories: 61.

| Bucket | Count | Action |
|---|---|---|
| Static, passes today | 32 | Bind to one CI step |
| Static, fails today | 3 (`dead-mans-switch`, `kepler-crash-monitoring`, `postgres-exporter-firewall`) | Delete; assertions name moved/renamed config, and the live intent is owned by the Kepler cold-restart proposal |
| Migration, subject deleted | 8 (`p1-swag-*` ×3, `p2-adguard-preflight`, `p3-adguard-outage`, `p3-generic-dhcp-client`, `discovery-esp-scratch-restore`, `orchestration`) | Delete |
| Runtime/manual (needs nix eval, docker, ssh, network) | 18 | Declare in `tests/MANUAL.md` with the command and why it cannot run in CI |

`harbor-version-reconcile` is in the manual bucket but references
`scripts/harbor-setup.sh`, which lives at
`modules/hosts/discovery/servarr-harbor/scripts/harbor-setup.sh`; repair the
path or delete it in S4.

Failure evidence (2026-10-31): `pytest -q tests/dead-mans-switch
tests/kepler-crash-monitoring tests/postgres-exporter-firewall` → 5 failed,
2 passed. Passing baseline: `pytest -q` over the 35 static dirs → 32 clean.

## Slices

### S1 — Hygiene guard (RED anchor)

**Observable result.** One runnable check states every invariant this change
claims, and fails on the pre-change tree.

**RED.** Add `tests/repository-hygiene/test_hygiene.py`. Run:

```
pytest -q tests/repository-hygiene
```

Expected failure on `d091d982`: 55 deleted-recipe names present, 22 `# Moved`
files, 61 unreferenced test directories, `wallpaper_old.png` present. Record the
counts in the slice receipt.

**GREEN surface.** The same file, unchanged, passes after S2–S5. Assertions:

1. `just --summary` contains no name matching
   `^discovery-(swag|adguard|docker|esp)-` except the six retained drills and
   diagnostics; none of the seven `p3-adguard-*`/`p3-generic-dhcp-client`
   names; none of the twenty one-off names listed in the keep/rebuild audit;
   and no `discovery-migration-inventory` or `discovery-telstar-state-inventory`.
2. No file under `docs/` contains a line equal to `# Moved`.
3. Every directory under `tests/` appears in `.github/workflows/`, the
   justfile, or `tests/MANUAL.md`.
4. `config/themes/wallpapers/wallpaper_old.png` does not exist.
5. The root justfile imports at least one `just/*.just` file.

**Verification command and marker.**

```
pytest -q tests/repository-hygiene && echo "S1 GREEN: HYGIENE ASSERTIONS PASS"
```

Marker prints only after zero exit.

**Owner / dependencies.** desktop-nixos; none.
**Rollout.** Land S1 together with S2 (the repository is red between them).
**Rollback.** Revert the merge.

### S2 — Remove finished-migration recipes and scripts

**Observable result.** `just --list` exposes no P1–P6 transition command; the
recovery and diagnostic set is unchanged.

**RED.** S1 assertion 1 fails on 82 names.

**GREEN surface.** Delete the recipe bodies named in proposal M1, M1b, and M1c
(82 recipes, 1,976 lines), then delete
`scripts/p3-adguard-outage-client.sh`, `p3-adguard-outage-drill.sh`,
`p3-adguard-outage-observe.sh`, `p3-generic-dhcp-client.sh`,
`p3-udhcpc-capture.sh`, and `modules/hosts/discovery/_p3-observation-recover.py`.
Remove recipe-private helpers left without a caller.

**Verification.**

```
just --summary | tr ' ' '\n' | sort > /tmp/recipes.after
! grep -E '^discovery-(swag|adguard|docker|esp)-' /tmp/recipes.after \
  | grep -vE '^(discovery-swag-restore-drill|discovery-adguard-(restore-(preflight|seed|finalize|drill)|exporter-diagnostic))$'
! grep -qxE 'discovery-(migration-inventory|telstar-state-inventory)' /tmp/recipes.after
! grep -qxE 'p3-(adguard-outage-(prepare|plan|observe|execute|cleanup)|adguard-observation-recover|generic-dhcp-client)' /tmp/recipes.after
grep -qx 'p3-dns-verify' /tmp/recipes.after
for keep in discovery-swag-restore-drill discovery-adguard-restore-drill \
            discovery-harbor-restore-drill discovery-haos-boot-drill \
            kepler-recovery-inventory deploy-rs update-safe; do
  grep -qx "$keep" /tmp/recipes.after || { echo "MISSING $keep"; exit 1; }
done
! git grep -nE 'p3-adguard-outage-(client|drill|observe)|p3-generic-dhcp-client|p3-udhcpc-capture' -- justfile
echo "S2 GREEN: RECIPES TRIMMED, CAPABILITIES RETAINED"
```

**Owner / dependencies.** desktop-nixos; none.
**Rollout.** Same PR as S1.
**Rollback.** Revert.

### S3 — Remove Discovery stateful-stack helpers

**Observable result.** Discovery no longer ships the retired migration CLI.

**RED.** `git grep -n 'stateful-stack-ops' -- modules` still matches; no
hygiene assertion covers this, so the RED is the presence check itself.

**GREEN surface.** Delete `modules/hosts/discovery/stateful-stack-ops.nix` and
the 15 `modules/hosts/discovery/_stateful-*` files (234,150 B), and remove
`m.nixos.discovery-stateful-stack-ops` from the import list in
`modules/hosts/discovery/default.nix:36`. Without that edit the flake fails
evaluation.

**Verification.**

```
! git grep -nE 'discovery-stateful-stack-ops|_stateful-' -- modules justfile scripts
just dry discovery && echo "S3 GREEN: DISCOVERY EVALUATES WITHOUT STATEFUL OPS"
```

**Owner / dependencies.** desktop-nixos; requires S2 (recipes gone first).
**Rollout.** Deployed only by a later `switch`; this change stops at eval.
**Rollback.** Revert; no runtime state moved.

### S4 — Test tree triage and one static gate

**Observable result.** Every test directory is either executed by a gate or
explicitly declared manual; the static set runs in CI.

**RED.** S1 assertion 3 fails for 75 directories (61 unreferenced, 14 docs-only).

**GREEN surface.**

- Delete the 8 migration directories and the 3 failing static directories.
- Repair or delete `tests/harbor-version-reconcile`.
- Add `tests/MANUAL.md` with one row per runtime directory: name, command,
  prerequisite, owning document. Include the 14 docs-only directories unless
  the slice binds them.
- Add one CI step: `pytest -q` over the 32 static directories plus
  `tests/repository-hygiene`.
- Add `just hygiene-check` delegating to the same command, and call it from
  `just check` so the local gate matches CI.

**Verification.**

```
pytest -q tests/repository-hygiene tests/ai-default-model tests/ssh-config
just hygiene-check
echo "S4 GREEN: TESTS GATED AND TRIAGED"
```

CI proves the full list; record its wall time in the receipt and fail the slice
if it exceeds 120 s.

**Owner / dependencies.** desktop-nixos; requires S2 (deleted subjects).
**Rollout.** CI step is additive; no host impact.
**Rollback.** Revert; test files return with the commit.

### S5 — Documentation single-record pass

**Observable result.** No pointer stubs; the index describes purpose only.

**RED.** S1 assertion 2 fails on 22 files.

**GREEN surface.** Delete the 22 `# Moved` stubs; point each affected README row
at the canonical homelab URL; rewrite `docs/README.md` without a status verdict
per row (target under 20 KB). Retain `.feature` contracts and one-pagers.

**Verification.**

```
just docs-check
pytest -q tests/repository-hygiene
test "$(wc -c < docs/README.md)" -lt 20000
echo "S5 GREEN: ONE CANONICAL RECORD PER DOCUMENT"
```

**Owner / dependencies.** desktop-nixos; independent of S2–S4 except the shared
hygiene test.
**Rollout.** Docs-only.
**Rollback.** Revert.

### S6 — Split the justfile by domain

**Observable result.** The root justfile holds variables, exports, `default`,
and the three private helpers plus `import` lines; recipe bodies live in fifteen
domain files with identical names and bodies.

**RED.** S1 assertion 5 fails: the root justfile has no `just/*.just` import.

**GREEN surface.** Create the files listed in the proposal's M2b with the counts
in the keep/rebuild audit, move recipe bodies verbatim, and add one `import`
line per file after the variable definitions. Use `import`, not `mod`, so every
existing invocation keeps its spelling. No recipe body edits.

**Verification.**

```
just --list --unsorted | sed -E 's/[[:space:]]+#.*//' > /tmp/after.txt
diff <(sort /tmp/recipes.before) <(sort /tmp/after.txt)
echo "S6 GREEN: RECIPE SET UNCHANGED BY SPLIT"
```

Capture `/tmp/recipes.before` at the start of S6.

**Owner / dependencies.** desktop-nixos; requires S2.
**Rollout.** No behavior change.
**Rollback.** Revert the split commit only.

## Grill findings (one round)

| Challenge | Finding | Applied |
|---|---|---|
| Are the deleted recipes truly unused? | `git grep` across six sibling repos and `homelab/docs` finds only the owning proposal. | Kept the proposal link in the runbook; no consumer edits. |
| Could a host unit call a deleted package? | Only `discovery-stateful-stack-fixture`, which is deleted in the same module. | S3 verification greps `modules/`. |
| Is binding 32 suites to CI safe? | All pass today; they are static and cwd-independent. | S4 is additive; cap 120 s. |
| Does deleting failing tests hide regressions? | The three failures assert exact strings that moved; the live intent is owned by the Kepler cold-restart proposal. | Deleted, with the intent recorded in the proposal. |
| Does the hygiene test become the new cruft? | It is one file and five assertions, each mapped to an accepted rule. | Kept; no per-directory fixtures. |
| Is the split worth it? | 7k lines of live recipes is a navigation problem, not a correctness one. | Conditional on the 4,000-line gate, mechanical only. |

## Integration and order

One branch, three commits: `chore(repo): drop finished migration tooling`
(S1+S2+S3), `test(repo): gate static contracts and declare manual suites`
(S4), `docs(repo): keep one canonical record per document` (S5). S6 is a fourth
commit only if the measurement triggers it. Rebase order is fixed by dependency;
no cross-repo change is required.
