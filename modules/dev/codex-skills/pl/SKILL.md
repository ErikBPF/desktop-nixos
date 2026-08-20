---
name: pl
description: Shape an ambiguous idea into an agreed decision map and BDD `.feature` contract before implementation planning. Use for `/pl`, `$pl`, conceptualization, product or architecture discovery, cross-repository changes, Party Mode elicitation, behavior mapping, or requests to plan what should be built. Skip the full ceremony for trivial documentation, wiring, or already-settled changes.
---

# Planning

Produce shared understanding, not an implementation plan or production code.

## Skill group

Use these capabilities in order when available:

1. **Repository grounding:** Graphify first when a graph exists, then verify
   operational claims in authoritative source.
2. **Discovery party:** use `$party` for bounded multi-perspective elicitation.
3. **Decision map:** use `$map` to preserve decisions, dependencies, fog, risks,
   and the next frontier.
4. **BDD:** read [references/bdd-feature.md](references/bdd-feature.md) and
   express agreed behavior as concrete, observable examples.
5. **Grill:** use `$grill` to pressure-test unresolved decisions and the final
   contract without inventing answers.

If a named capability is unavailable, perform its equivalent directly and say
which fallback was used.

## Workflow

1. Capture the human seed: destination, motivation, constraints, and non-goals.
   Do not silently originate load-bearing requirements.
2. Resolve repository ownership, existing vocabulary, related decisions,
   behavior, and constraints from source.
3. Run `$party`. Preserve disagreements; do not manufacture consensus.
4. Run `$map`. Reuse an existing proposal or spec instead of creating another
   artifact.
5. Write or update a `.feature` file from agreed behaviors in the repository
   that owns the behavior. Questions stay questions; they do not become
   scenarios.
6. Run `$grill`, apply accepted improvements, and update `$map`. Stop after two
   critique rounds unless new evidence appears.

Finish when the destination, non-goals, mental map, scenarios, and blockers are
explicit enough for `$ip`.
