---
name: pl
description: Ground an ambiguous idea in source; agree a decision map and BDD contract before implementation planning. Use for /pl, $pl, discovery, conceptualization, architecture or cross-repository planning. Skip full ceremony for trivial or settled work.
---

# Planning

Produce shared understanding, not code or an implementation plan. Default:
`/pl` → `/ip` → implementation → `/rv`. RFC → ADR → spec is explicit-request-only;
prepare a requested RFC when ready for human feedback.

1. Preserve the human seed verbatim. Separately record destination, motivation,
   constraints and non-goals. Never invent load-bearing requirements.
2. Ground questions in ownership, vocabulary, decisions, behavior and source
   before refinement. Query existing Graphify first; verify operational claims
   in authoritative source. Read repository environment preferences.
3. Use `$party` for bounded elicitation; preserve disagreement, not false consensus.
4. Use `$map` for decisions, dependencies, unknowns, risks and next frontier.
   Reuse existing artifacts.
5. Read [references/bdd-feature.md](references/bdd-feature.md). Write concrete,
   observable agreed examples in the owning repository's `.feature` contract.
   Unanswered questions must not become scenarios.
6. Use `$grill` on unresolved decisions and the final contract; apply accepted
   improvements and update the map. Stop after two critique rounds unless new
   evidence appears. If a capability is unavailable, apply and name its fallback.

For substantial work, preserve the discovery revision and obtain a fresh
independent read without a fixed delay. Rewrite like you know the end: organize the map
and examples backward from the supported outcome; cut tangents, retain receipts
and unresolved questions. Keep seed integrity and accepted principles.

Apply shared feedback policy: queue questions, emit the PL one-pager and hand it
to `/cr` when human feedback is needed. Finish when destination, non-goals, map,
scenarios and blockers support `$ip`.
