---
name: pl
description: Shape an ambiguous idea into an agreed decision map and BDD `.feature` contract before implementation planning. Use for `/pl`, `$pl`, conceptualization, product or architecture discovery, cross-repository changes, Party Mode elicitation, behavior mapping, or requests to plan what should be built. Skip the full ceremony for trivial documentation, wiring, or already-settled changes.
---

# Planning

Produce shared understanding, not an implementation plan or production code.
Default entry to `/pl` → `/ip` → implementation → `/rv`; RFC → ADR → spec is
required only when explicitly requested. Prepare a requested RFC when the work
is ready for human feedback; do not require formal documents to begin planning.

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

1. Preserve the human seed verbatim; record destination, motivation, constraints
   and non-goals separately. Ground questions before refinement. Do not silently
   originate load-bearing requirements.
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

Before handing off substantial work, preserve the discovery draft and obtain a
fresh independent read without a fixed delay. Rewrite like you know the end:
organize the map and behavior examples backward from the supported outcome,
remove exploratory tangents from the final artifact, and retain their receipts.
Do not turn unresolved questions into accepted behavior. Finish when destination,
non-goals, map, scenarios and blockers are explicit enough for `$ip`.

Apply the shared evidence-and-feedback policy: preserve the raw seed, read the
repository environment preferences, queue unresolved questions, and emit the PL
one-pager. Keep the accepted principles visible when refining a new workflow.
