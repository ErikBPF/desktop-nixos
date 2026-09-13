---
name: rv
description: Review and revise plans, documents, diffs, branches or PRs through independent conformance, correctness, security, editorial and simplicity passes. Use for /rv, $rv, review everything or final review; fix verified findings and rerun checks. Publishing requires explicit authorization.
---

# Review and Revise

Default target: current task's artifact/diff. Resolve seed, fixed point, accepted
behavior, plan and repository rules; clarify only what cannot be inferred safely.
Refuse empty/ambiguous diffs; never substitute unrelated work. Accepted PL/IP outcomes suffice;
RFC/ADR/spec is explicit-request-only.

1. For substantial work, preserve first-draft revision/evidence; obtain fresh
   independent review without a fixed delay. Keep findings from separate passes:
   - conformance: accepted behavior and repository rules;
   - correctness: bugs, regressions, races and error paths (`/review`, caveman-review);
   - security and applicable reliability, performance, architecture, test,
     compatibility, operations/accessibility risks (`$codehero`);
   - adversarial: BMAD Code Review Crew;
   - load-bearing documents: BMAD editorial structure, then prose.
   Use available equivalents. Delegates review directly: no nested RV/review tree.
2. Verify findings in source or reproduce; rank impact, discard unsupported claims.
3. Fix bugs after a verified failing regression check. For behavior drift, return
   to accepted contracts; for document defects, preserve intent and apply accepted correction.
4. Rewrite like you know the end: state the observed accepted outcome, work
   backward through boundaries, interfaces, names and rationale; cut experiments,
   temporary glue and tangents. Run simplicity (`/simplify`, Ponytail or
   ponytail-review) after correctness. Preserve behavior, seed, receipts and RED
   anchors; never backdate tests or invent certainty.
5. Rerun bound scenarios, focused tests, relevant suite and repository checks on
   final edits. Repeat once only for new validation evidence; otherwise stop and
   report blockers. Never claim a scenario passed without running its bound runner.

Return changed files, fixed/discarded findings, commands/results and open risks
in the RV one-pager. Apply shared feedback policy: task-bound tuicr/Neovim for
needed human input; reconcile returned points by revision and report feedback.
Closing a window or writing a report is not approval. Do not publish comments,
commits or pushes without explicit authorization.
