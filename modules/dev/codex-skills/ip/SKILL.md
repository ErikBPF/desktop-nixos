---
name: ip
description: Convert an accepted proposal, spec, or BDD `.feature` contract into a repository-grounded vertical implementation plan. Use for `/ip`, `$ip`, or when settled behavior needs test seams, RED-GREEN slices, dependencies, verification commands, rollback gates, ownership, or a plan grill before coding. Return to planning instead of inventing missing behavior.
---

# Implementation Plan

Plan the build; do not implement it. Accept the human seed and settled `/pl`
outcome without requiring RFC/ADR/spec documents. The formal flow applies only
when explicitly requested; preserve seed integrity and accepted test gates.

## Skill group

Use `$map` for accepted decisions, the available TDD skill for delivery slices,
`$codehero` for review-gate selection, and `$grill` for plan pressure-testing.
If unavailable, apply their equivalent directly.

## Workflow

1. Read the human seed, accepted planning artifact and applicable `.feature`
   contract completely. If the
   destination or behavior remains disputed, stop and return to `$pl`.
2. Trace the affected flow, callers, ownership, repository conventions, test
   harness, deployment path, and rollback path.
3. Name candidate public test seams with what each catches, misses, and costs.
   Select the fewest useful seams and record the choice.
4. Map each scenario to one vertical slice. Every slice must own what it grades
   and answer, "What observable behavior can be demonstrated when this lands?"
5. Write each slice with:
   - scenario and observable result;
   - RED test or bound feature scenario, command, and expected failure;
   - minimum GREEN implementation surface;
   - focused and broader verification;
   - dependencies, owner, rollout, and rollback where relevant.
6. Order cross-repository work leaf-first, then consumers, then deployment.
7. Run `$grill` on the complete plan for at most two rounds:
   - Anti-Consensus Club: alternatives, evidence, repetition, easy agreement.
   - Advanced Elicitation: Assumption Audit, Pre-mortem Analysis, and Boundary &
     Edge Case Sweep.
   - CodeHero: applicable security and specialist review gates, evidence,
     ownership, and rollback expectations.
8. Apply accepted findings and rerun the plan checks. Reopen planning when a
   finding changes behavior rather than delivery.

Prefer one implementation artifact: update the existing proposal, spec, or
issue list. Do not scaffold speculative tickets or abstractions.

Before handing off a substantial plan, preserve its discovery revision, obtain
a fresh independent read without a fixed delay, and rewrite the slices backward
from the accepted outcome: clarify dependencies and test seams, remove obsolete
steps, and retain the discovery evidence. Do not change accepted behavior.

Apply the shared evidence-and-feedback policy. Include the implementation's first-draft snapshot,
fresh independent review without a fixed delay, rewrite from the observed
outcome, and final RV in the slice plan. Define useful green PR boundaries and
predecessors, plus any separately authorized live target and bounded test loop.
Emit the IP one-pager; queue missing input while independent work continues.
