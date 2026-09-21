---
name: ip
description: Turn accepted behavior into a repository-grounded vertical implementation plan with test seams, RED-GREEN slices, ownership, verification and rollback. Use for /ip, $ip or implementation planning; reopen planning for missing behavior.
---

# Implementation Plan

Plan; do not implement. Human seed and accepted `/pl` outcomes suffice;
RFC/ADR/spec is explicit-request-only. Preserve seed integrity and test gates.

1. Read the seed, accepted planning artifact and applicable `.feature` contract
   completely. Disputed destination or behavior returns to `$pl`.
2. Trace callers, flow, ownership, conventions, tests, deployment and rollback.
3. Compare public test seams: coverage, omissions, cost. Record the fewest useful.
4. Map scenarios to vertical slices that own what they grade. Each specifies:
   - observable result and scenario;
   - RED test/bound scenario, command and expected failure;
   - minimum GREEN surface;
   - an exact verification command and the success-only marker it prints only
     after every assertion passes (zero exit plus marker); a criterion that
     cannot be made runnable becomes an explicit handoff or abandon, never a
     silent omission;
   - owner, dependencies, rollout and rollback.
5. Use `$map` for decisions, available TDD for slices, `$codehero` for risk gates.
   Order useful green PRs leaf-first, then consumers, then deployment; name
   predecessors. Specify any authorized live target and bounded campaign.
6. Grill the complete plan with `$grill`, at most two rounds: challenge easy
   consensus and alternatives; audit assumptions, pre-mortem, boundaries and
   edge cases; check security/specialist risks, evidence, ownership and rollback.
   Apply accepted findings and rerun checks; behavior changes return to `$pl`.
   Use direct equivalents when supporting skills are unavailable.

Author each verification so it can fail honestly: observe the outcome directly,
print the success marker only after all assertions pass, test absence checks
against a known positive control, measure supplied figures independently rather
than copying them into the expectation, and rerun with the same shell and
toolchain the slice declares.

Reuse one planning artifact; no speculative tickets or abstractions. For a
substantial plan, preserve discovery, obtain fresh independent review without a
fixed delay, then rewrite slices backward from accepted outcomes. Clarify seams
and dependencies, cut obsolete steps, retain evidence and accepted behavior.

Plan implementation's snapshot, fresh review, backward rewrite and final RV too.
Apply shared feedback policy: emit the IP one-pager, hand it to `/cr` when human
feedback is needed, queue missing input and continue independent work.
