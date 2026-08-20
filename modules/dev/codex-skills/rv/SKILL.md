---
name: rv
description: Review and revise a plan, specification, document, working-tree diff, branch, or pull request through independent conformance, correctness, security, editorial, and simplicity passes; apply verified fixes and rerun validation. Use for `/rv`, `$rv`, "review everything", "revise everything", final completion review, or when review plus simplify should run as one bounded workflow. Do not publish comments, commits, or pushes unless explicitly authorized.
---

# Review and Revise

Review, fix, simplify, verify. Default target: the current task's changed
artifact or diff. Ask for a fixed point only when it cannot be inferred safely.

## Skill group

Use available equivalents; names vary by harness:

- **Conformance:** spec and repository-standard comparison.
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

1. Resolve the target, fixed point, accepted behavior, implementation plan, and
   relevant repository rules. Refuse an empty or ambiguous diff rather than
   reviewing unrelated work.
2. Run independent passes without letting one erase another's findings:
   - conformance: right behavior and repository rules;
   - correctness: bugs, regressions, races, unexpected behavior, error paths;
   - CodeHero security and other applicable specialist risks;
   - editorial structure and prose for load-bearing documents.
3. Verify every finding against source or reproduce it. Rank by impact; discard
   unsupported findings.
4. Revise:
   - code bug: add or identify a failing regression check, verify RED, then fix;
   - behavior drift: return to the accepted contract instead of rewriting it;
   - document defect: preserve intent while applying the accepted correction.
5. Run the simplicity pass after correctness fixes. Apply only behavior-
   preserving deletion, reuse, naming, efficiency, and abstraction reductions.
6. Rerun bound `.feature` scenarios, focused tests, the relevant suite, and
   repository checks after final edits.
7. Repeat once only if final validation exposes new evidence. Otherwise stop
   and report the remaining blocker.

Return changed files, verified findings fixed, discarded findings, validation
commands and results, and unresolved risks. Never claim a `.feature` scenario
passed unless its bound runner actually ran.
