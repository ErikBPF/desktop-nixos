# Repository simplification: GREEN

**Stage / revision:** GREEN / 3
**Status:** Implemented on the task branch — pending review and publication
**Owner / date:** desktop-nixos / 2026-11-01
**Basis:** PL/2 proposal and contract, IP plan, keep/rebuild audit

## Outcome and why it matters

The repository now runs one executable path per live operation: 82 recipes,
13 test directories, five scripts, one helper tree, and 22 pointer stubs are
gone; the justfile is split into fifteen imported files; every test directory is
either gated or declared manual. The seed's three complaints — one-off tests,
unnecessary just commands, situational files — are answered by a hygiene test
that fails if any of them returns.

## What changed

| Area | Change |
|---|---|
| Recipes | 374 → 293; 82 deleted (62 finished phases, 20 one-offs) |
| Moved modules | 55 transition recipes, 16 AdGuard, 7 Docker, 2 ESP, 2 audits, 7 P3, 20 one-offs |
| Split | Root keeps variables, `default`, 3 private helpers, 15 `import` lines; 15 `just/*.just` files hold bodies verbatim |
| Tests | 115 → 103 directories; 13 deleted, 32 static suites added to CI, 32 runtime suites in `tests/MANUAL.md` |
| Scripts | 5 P3 scripts and `_p3-observation-recover.py` deleted |
| Modules | Discovery stateful-stack package and 15 helpers deleted; `drtest` throwaway VM and its deploy node deleted |
| Docs | 22 `# Moved` stubs deleted; index 36 KB → 13.7 KB with no status restatement |
| Guard | `tests/repository-hygiene` + `just hygiene-check`, wired into `just check` and CI |

The rejected alternative was `mod` namespacing, which would have renamed every
invocation. `import` preserves `just deploy-rs`, `just check`, and CI calls.

## Evidence and limits

| Claim / scenario | Evidence | Result and limitation |
|---|---|---|
| Hygiene invariants | `just hygiene-check` | Pass |
| Docs links | `just docs-check` | Pass |
| Nix formatting and lint | `just fmt-check`, `just lint` | Pass |
| Structure contract | `just structure-check` | Pass (advisory warnings only) |
| Discovery evaluates | `just dry discovery` | Exit 0 |
| 32 static suites | `pytest -q` per directory | All pass |
| Affected gated suites | `build-process`, `update-safe`, `ha-harbor-reader`, `discovery-secret-contract`, `dendritic-structure`, `homelab-iac-drift`, `servarr*`, `cognee-*`, `orion-upgrade-diagnostics` | Pass after reader updates |
| Full `just check` | not run | `dry-all` builds five host closures; CI covers it |
| Live behavior | not observed | No host was switched or deployed |

Two manual suites still fail as they did before the change: `kepler-compose`
(assertion about declared units) and `grafana-alert-ops` (a `Restart` assertion).
Both are in `tests/MANUAL.md`; neither is gated.

## Decisions and corrections

| ID | Decision or correction | Consequence | Blocks |
|---|---|---|---|
| C-1 | Keep `voyager-vm-*` deleted; the implemented doc now carries the build/test commands | One historical gate loses its wrapper | none |
| C-2 | Delete the `drtest` VM module and deploy-rs node rather than restore its lifecycle recipes | Removes a throwaway PoC that no fleet host used | none |
| C-3 | Delete three test assertions whose only subject was a deleted one-off recipe | `cognee-recovery`, `servarr-exact-revision`, `grafana-alert-ops`, `homelab-iac-drift` shrink | none |
| C-4 | 34 test files now read `justfile` plus `just/*.just` | The split cannot silently hide a recipe from a contract test | none |

## What continues / what waits

The branch holds one commit. Review is the next step, then publication.
Worktree and branch cleanup (55 worktrees, 87 branches) remains deferred and
needs explicit authorization.

## Risks and recovery

- **A contract test now parses concatenated text.** It could mask a recipe that
  moved but changed name; `just --summary` parity and the hygiene test cover the
  name set, not the body. Review the split diff with moved-file detection.
- **Two manual suites are red before and after.** They are declared manual; a
  green claim never included them.
- **Rollback.** Revert the commit; no host state changed.
