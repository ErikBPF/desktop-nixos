# S04 source test contract and receipts

**Status:** Source validation in progress; live systemd and notification proof pending.

Human seed: “do remaining core work” — S04 pilot and S10 closeout; seven-day
evidence cannot be fabricated. Subsequent explicit scope answer: Downloads only.

Initial callable seam returned state unchanged; six real assertions failed:
synthetic finding did not clear, stale digest/concurrent job/genuine receipt/
non-private receipt were accepted, and actual canary did not produce a finding.
The implementation then passed those tests. No missing-file failure is counted
as behavioral RED.

Independent review added four substantive failures before repair:

- A genuine progress finding with no final receipt was cleared as synthetic.
- A genuine marker written before a crash in counter publication did not block
  a subsequent synthetic canary.
- Direct scheduled runner execution launched while the backup lock was held.
- A backup process acquired its lock during the actual integrity command.

Genuine markers now precede state validation/publication, have unique event IDs,
and cannot be cleared by the pilot. No timestamp or baseline digest authorizes
ignoring an older genuine marker. An audit-write failure also leaves findings
unchanged. Fixtures prove partial/error state and completion time remain intact.

The pinned scanner initially reported a forced `--max-filesize=1` heuristic as
an error (exit 2), rather than a partial-only exit. The helper does not disguise
that failure. Its partial case instead scans a clean harmless synthetic subset
and explicitly reports the declared Downloads scope as uncovered. Error case
uses an absent private fixture database; finding case uses a private custom
signature. Neither touches real Downloads or selected production definitions.

Backup source grounding: pinned NixOS Restic `backupPrepareCommand` runs in a
separate preStart child process, so a lock FD there would not span ExecStart.
The package wrapper holds the lock for every actual Restic invocation, preserving
upstream argument/environment/preparation/cleanup ownership. Cross-invocation
service activity is not described as non-overlapping data work.

The first staged Nix assertion failed because Endeavour collection remained
disabled. Final stage checks additionally cover explicit `--store daemon`,
backup root/sandbox/tmpfiles ordering and shared lock accessibility. A missed
text replacement initially omitted those latter assertions; the corrected file
is the authoritative final gate.

No live host write, deployment, backup repair, ordinary-file scan, notification
receipt or elapsed observation is represented by these local tests.
