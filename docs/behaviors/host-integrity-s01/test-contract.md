# S01 test contract and evidence

The accepted S01 packet and interface supply the test scope; no additional
behavior or production activation is inferred from local tests.

- Reporter: never-run output, private state permissions, restart persistence,
  failed/partial/clean-run retention, invalid identity/value rejection, injected
  replacement failure, recovery after interruption, malformed persisted values.
- Collector: evaluate enabled and disabled synthetic Nix modules; validate the
  complete generated Alloy configuration with pinned Alloy; run only selected
  textfile/relabel components against temporary fixtures and an echo sink.
  A positive backup metric must survive while forged legacy integrity metrics
  disappear. Trusted input gets the configured instance and no private labels.
- Repository: lint, format, structure check, real Endeavour toplevel dry-run.
  These are evaluation/static gates, not deployed behavior tests.

## RED anchors

2026-11-20: `pytest -q tests/host-integrity/test_reporting.py --tb=line`
failed 11 assertions because the reporter did not exist (the initial fixture
setup-error run was corrected and is not counted as RED).
`pytest -q tests/alloy --tb=short` failed the new legacy-drop assertion while
both existing tests passed. Three subsequent malformed-state cases failed with
`DID NOT RAISE ValueError`, then passed after validation was tightened.

## GREEN and repair log

Reporter: 14 tests passed after implementation. Combined first collector run:
15 passed before the final three persisted-value cases were added. Final suite
command and count are recorded in the stage one-pager.

Collector fixture repairs: Nix `eval --file` returns a function without applying
arguments, so the common fixture moved to `_fixture.nix` and `evaluate.nix`
remains a no-argument gate. Then the fixture's accelerated one-second scrape
needed an explicit one-second timeout. Both were harness failures, not RED.
Production's thirty-second interval validated unchanged.

Structure checker repair: it counts an unquoted module reference as a duplicate
registration. Quoting the attribute on the reference preserves Nix semantics and
passes the existing checker. First host dry-run failed because edits changed its
source snapshot during evaluation; rerun only after source freeze.

## Independent review revision

Reviewer reproduced boolean `database_seconds=True` poisoning persisted state.
A regression failed with `DID NOT RAISE ValueError`; strict numeric type checking
now rejects it before either file changes. The disabled Nix fixture now leaves
enablement unset and asserts the default is false. Collision assertions parse
the echo payload rather than searching timestamp digits. The first frozen
Endeavour dry-run passed (exit 0); final checks follow the revised source.

Final revised suite: `ALLOY_BIN=<pinned grafana-alloy>/bin/alloy pytest -q
tests/host-integrity tests/alloy --tb=short` — 19 passed in 8.12s.
Lint, format and structure gates passed; synthetic module eval returned
`S01_MODULE_EVAL_OK`; final frozen Endeavour `nix build ... --dry-run --offline`
exited 0. Only existing repository advisory/deprecation warnings remained.
