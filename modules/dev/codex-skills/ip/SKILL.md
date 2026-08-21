---
name: ip
description: Convert an accepted proposal, spec, or BDD `.feature` contract into a repository-grounded vertical implementation plan. Use for `/ip`, `$ip`, or when settled behavior needs test seams, RED-GREEN slices, dependencies, verification commands, rollback gates, ownership, or a plan grill before coding. Return to planning instead of inventing missing behavior.
---

# Implementation Plan

Plan the build; do not implement it.

## Skill group

Use `$map` for accepted decisions, the available TDD skill for delivery slices,
`$codehero` for review-gate selection, and `$grill` for plan pressure-testing.
If unavailable, apply their equivalent directly.

## Workflow

1. Read the accepted planning artifact and `.feature` file completely. If the
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
