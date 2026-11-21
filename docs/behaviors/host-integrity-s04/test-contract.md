# S04 source test contract and receipts

**Status:** Source validation passed; live systemd and notification proof pending.

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

## Final source validation

Reviewed implementation committed as `342a74f0`; these gates passed against the
frozen source before publication:

- CI-mode `pytest -q --import-mode=importlib tests/host-integrity tests/alloy`
  with pinned ClamAV 1.5.4 and Alloy 1.21.3: **70 passed**.
- `just lint`, `just fmt-check`, `just structure-check`, `just docs-check`:
  **passed**; structure advisories identify existing large files.
- Offline evaluation of `tests/host-integrity/evaluate.nix`:
  `S01_MODULE_EVAL_OK S02_MODULE_EVAL_OK`.
- Offline evaluation of `tests/host-integrity/pilot-evaluate.nix`:
  `S04_STAGED_PILOT_EVAL_OK`, including the corrected backup/store assertions.
- Endeavour toplevel `nix build --dry-run --offline`: **passed**, exit 0.
  Log: `/tmp/host-integrity-s04-host-dry.log` (local execution evidence).
- Working and staged `git diff --check`: **passed**.

Fresh independent review passed, including its own 66 helper tests and complete
S04 evaluation. No material source blocker remains. Existing Rofi/PipeWire
deprecation warnings do not establish runtime failure.

The precommit evaluated candidate was
`/nix/store/xyl7k4b6npkj2r4xik658crj4m8cg6vm-nixos-system-endeavour-26.11.20261115.5c3cda7`.
It was **not realized**; the offline dry-run listed **2256 derivations to build**.
This count is not proof that all are unrelated upgrades. Re-evaluate the published
revision, build through the owner workflow and inspect the candidate/current
closure difference before activation; commit metadata can change the candidate.
No host build or activation was performed by this validation pass.

The commit's actual hooks passed. Its ignored generated pre-commit configuration
was restored from the evaluated shell-hook configuration store path; an offline
full development-shell attempt was stopped after queuing excessive builds.
No hook was bypassed. These preparation details do not substitute for live
sandbox, backup exclusion, notification delivery or seven-day observation proof.
