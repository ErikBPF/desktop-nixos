---
name: rv
description: Review and revise a plan, specification, document, working-tree diff, branch, or pull request through independent conformance, correctness, security, editorial, and simplicity passes; apply verified fixes and rerun validation. Use for `/rv`, `$rv`, "review everything", "revise everything", final completion review, or when review plus simplify should run as one bounded workflow. Do not publish comments, commits, or pushes unless explicitly authorized.
---

# Review and Revise

Review, fix, simplify, verify. Default target: the current task's changed
artifact or diff. Ask for a fixed point only when it cannot be inferred safely.
Preserve the human seed through review; accepted `/pl` and `/ip` outcomes suffice.
Do not demand RFC/ADR/spec documents unless the user requested that formal flow.

## Skill group

Use available equivalents; names vary by harness:

- **Conformance:** accepted behavior and repository-standard comparison.
- **Correctness:** `/review`, code review, or caveman-review.
- **Specialist risks:** `$codehero` for security and every other applicable
  reliability, performance, architecture, test, compatibility, operations, or
  accessibility perspective.
- **Adversarial:** BMAD Code Review Crew.
- **Documents:** BMAD editorial structure then prose review.
- **Simplicity:** `/simplify`, Ponytail, or ponytail-review.

Delegated reviewers must review directly: they may not invoke `rv` or spawn a
nested review tree.

## Workflow

1. Resolve the human seed, target, fixed point, accepted behavior, plan, and
   relevant repository rules. Refuse an empty or ambiguous diff rather than
   reviewing unrelated work.
2. For substantial work, preserve the first-draft revision and evidence before
   a fresh independent review; no fixed waiting period. Run independent passes
   without letting one erase another's findings:
   - conformance: right behavior and repository rules;
   - correctness: bugs, regressions, races, unexpected behavior, error paths;
   - CodeHero security and other applicable specialist risks;
   - adversarial: BMAD Code Review Crew or a direct equivalent;
   - editorial structure and prose for load-bearing documents.
3. Verify every finding against source or reproduce it. Rank by impact; discard
   unsupported findings.
4. Revise:
   - code bug: add or identify a failing regression check, verify RED, then fix;
   - behavior drift: return to the accepted contract instead of rewriting it;
   - document defect: preserve intent while applying the accepted correction.
5. Rewrite like you know the end after correctness fixes: state the observed
   accepted outcome, work backward through boundaries, interfaces, names and
   rationale, and remove dead experiments, temporary glue and tangents from the
   final delivery. Keep first-draft receipts and RED anchors. Apply the simplicity
   pass without changing accepted behavior, backdating tests or inventing certainty.
6. Rerun bound `.feature` scenarios, focused tests, the relevant suite, and
   repository checks after final edits.
7. Repeat once only if final validation exposes new evidence. Otherwise stop
   and report the remaining blocker.

Return changed files, verified findings fixed, discarded findings, validation
commands and results, and unresolved risks. Never claim a `.feature` scenario
passed unless its bound runner actually ran.

Apply the shared evidence-and-feedback policy. Review the frozen first draft
independently before the second-draft rewrite; preserve discovery receipts and
verify the final result against the original seed and accepted contract. Emit
the RV one-pager and open a task-bound tuicr/Neovim handover when human feedback
is needed. Reconcile returned points by artifact revision, then report the
feedback stage. A report or closed review window is not approval.
