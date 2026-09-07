# Safe lock candidate

**Status:** Implemented locally; nine command cases pass; merge pending.

Human seed: harden `update-safe` from the proposal implementation shortlist.
Owner: desktop-nixos. Scope: the U1 lock transaction from the fleet-upgrade
proposal; no candidate evidence writer, input update on this checkout, or rollout.

Settled behavior: reject staged or unstaged `flake.lock` edits before invoking
Nix. Preserve original bytes on update failure, dry-build failure, INT or TERM.
Keep the candidate only after both commands succeed. Never reconstruct from Git.

Planning perspectives: operator requires index preservation; reliability requires
one shell spanning update and cleanup; simplicity keeps the existing recipe.
The alternative Git restore loses staged state and cannot preserve clean-filter
working-tree bytes. No unresolved behavior decisions remain in this scope.
SIGKILL, power loss, and concurrent lock writers are outside this transaction.

[Behavior contract](update-safe.feature) is unautomated Gherkin, with equivalent
command regressions in `tests/update-safe/test_update_safe.py` (no step bindings).

Implementation plan: one vertical slice edits the existing recipe and adds one
stdlib unittest command harness plus its CI invocation. Harness runs real Just
and Git in disposable repositories; only external update/build commands are
stubbed. Compare exact lock bytes and staged content and absence of leftover backup files.
RED: staged refusal and failed-update restoration fail against current recipe.
GREEN: index guard, temporary copy, EXIT cleanup, explicit INT/TERM exits.
Verify with `python3 -m unittest discover -s tests/update-safe -v`, `just lint`,
`just fmt-check`, and `just docs-check`. No host configuration changes; host
builds and fleet rollout are outside this slice. Revert the recipe change for
rollback; no migration or runtime activation is involved.

Plan grill: use a real clean-filter case to catch restoration from HEAD; signal
both update and dry-build phases; keep backup if restoration fails. Ensure the
cleanup trap is in the same shell as update, and restore only on failure.

Review evidence: staged refusal and six restore cases were observed RED before
the recipe change; all nine cases now pass. Real Git clean-filter bytes catch
HEAD-based restoration. INT/TERM doubles signal the recipe but exit successfully,
so the check requires actual signal handling. Lint, format, and documentation
checks pass. No global configuration, lock file, or running host was changed.
