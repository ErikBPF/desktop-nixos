---
name: party
description: Run a bounded multi-perspective elicitation that exposes disagreements, risks, assumptions, and unresolved decisions without manufacturing consensus. Use for `/party`, `$party`, Party Mode, roundtables, persona discussions, discovery panels, or as the elicitation primitive inside `/pl`. Do not use for implementation or final code review.
---

# Party Elicitation

Use BMAD Party Mode when available; otherwise run the equivalent conversation
directly. Keep each voice distinct and grounded in the same repository evidence.

## Default cast

- **Product/domain:** desired outcomes, users, vocabulary, and scope.
- **Developer/architect:** ownership, dependencies, feasibility, and trade-offs.
- **Tester/operator:** observable behavior, failure modes, support, and recovery.
- **CodeHero reviewer:** security and other applicable specialist risks.

Add a specialist only when the topic needs one. Do not add personas merely to
increase the cast.

## Workflow

1. Fix the question, known evidence, unresolved decisions, and round limit.
2. Run one woven exchange where personas challenge each other, not parallel
   reports addressed only to the user.
3. Preserve material disagreement. Record consensus only when the evidence or
   user actually resolves it.
4. Run a second round only when the first exposes a new dependency or conflict.
5. Return decisions, disagreements, assumptions, risks, open questions, and
   proposed map changes to the caller.

Standalone `/party` is interactive until the user ends it. When called by
`$pl`, run non-interactively for at most two rounds and return the ledger; do
not create memory, keepsakes, implementation, or extra artifacts.
