# Upgrade candidate evidence

Status: Implementation authorized by the September 12 continuation of the
accepted fleet-upgrade U1 slice. No host activation is included.

Provenance: homelab `docs/proposals/2026-07-12-fleet-upgrade-hardening.md`,
remaining implementation and U1; the historical
[update-safe seed](../update-safe/behavior.md) remains unchanged. This extends
the completed transaction with its previously deferred evidence writer.

## Contract

```yaml
command: just update-safe
owner: desktop-nixos
output: git rev-parse --git-path upgrade-candidate.json
publish: atomic replacement after update and dry-all succeed
fields:
  baseline_revision: exact Git HEAD commit
  before_lock_sha256: SHA-256 of preserved working-tree lock bytes
  candidate_lock_sha256: SHA-256 of successfully checked candidate lock bytes
  checked_at: UTC ISO-8601 timestamp
  validation: dry-all
failure:
  lock: restore original working-tree bytes using existing transaction
  previous_receipt: preserve
  temporary_receipt: remove
secrets: no lock contents, URLs, environment, or command output
tests: python3 -m unittest discover -s tests/update-safe -v
```

The pair of lock digests identifies exact input states, including changes to
non-Git inputs and follows edges, without parsing or copying sensitive lock
metadata. The Git revision identifies the source baseline; it does not assert
that unrelated source files are clean or that the revision is published.

This receipt records the existing `dry-all` check, not realized builds,
affected-host classification, rollout authorization, or runtime acceptance.
An older receipt remains historical after failure; compare its candidate
digest with the current lock before using it. Each linked worktree has its
own Git metadata path.

## Verification

Extend the existing real Just/Git disposable-repository check. Preserve staged
and unstaged refusal, update/build failures, INT/TERM handling, and Git clean
filter coverage. Add exact successful receipt fields and timestamp, synthetic
secret exclusion, preservation of previous receipts on failure, and lock
restoration when receipt publication fails. No real Nix update or fleet
operation runs in this test.

Rollback: revert the writer and its recipe call; keep the existing transaction.
