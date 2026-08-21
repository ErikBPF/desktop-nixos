---
name: map
description: Create or maintain a decision map for an ambiguous or multi-part effort. Use for `/map`, `$map`, mental maps, decision maps, wayfinding, dependency mapping, fog-of-war tracking, or as the mapping primitive inside `/pl`. The map decides what must be settled; it does not contain implementation tasks or build code.
---

# Decision Map

Keep one low-resolution view of what is known, decided, blocked, and still
unclear. Update an existing proposal or spec by default; do not create a second
artifact merely to hold the map.

## Map shape

- **Destination:** the observable end state and why it matters.
- **Actors and outcomes:** who interacts with the result and what changes.
- **Decisions:** settled choices, evidence, owner, and consequences.
- **Dependencies:** which decisions or external facts block others.
- **Fog:** important unknowns that cannot yet be phrased as precise questions.
- **Open questions:** precise decisions still requiring evidence or a human.
- **Risks and review gates:** failure impact and required specialist checks.
- **Out of scope:** branches explicitly excluded from the destination.
- **Frontier:** open, unblocked questions that can be resolved next.

## Rules

1. Resolve repository facts from source; do not turn them into user questions.
2. Write every open decision as a question. Move build tasks downstream to
   `$ip` instead of disguising them as decisions.
3. Link to detailed evidence rather than copying it into the map.
4. Update the map after party or grill findings; remove resolved fog and retain
   rejected branches under out of scope.
5. Keep the map inline for work that fits one session. Use a standalone map
   artifact only when the effort genuinely spans sessions or repositories.

The map is clear when the destination is stable and no open decision blocks a
BDD contract or implementation plan. Hand control back to `$pl`; never build.
