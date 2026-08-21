---
name: grill
description: Pressure-test an idea, decision map, specification, or implementation plan and improve it without writing production code. Use for `/grill`, `$grill`, plan grilling, assumption audits, pre-mortems, first-principles critique, red teams, or as the refinement primitive inside `/pl` and `/ip`.
---

# Grill

Use BMAD Advanced Elicitation when available. Separate facts the repository can
answer from decisions only the user can make.

## Workflow

1. Fix the target, accepted behavior, unresolved questions, and round limit.
2. Resolve factual questions from authoritative source before asking the user.
3. Walk decisions in dependency order. In an interactive grill, ask one concise
   question at a time, include a recommendation and trade-off, then wait.
4. Apply the smallest relevant lenses:
   - alternatives and first principles;
   - assumption audit and evidence check;
   - pre-mortem, boundaries, and edge cases;
   - sequencing, ownership, verification, rollout, and rollback;
   - CodeHero security and specialist review gates when applicable.
5. Show findings and proposed changes. Preserve rejected proposals and unresolved
   decisions instead of silently rewriting accepted behavior.
6. Recheck the revised target once. Stop after two rounds unless new evidence
   appears.

When called by `$pl` or `$ip`, return verified improvements and blockers to the
caller. Never answer a human decision on the user's behalf and never continue
into implementation.
