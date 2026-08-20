---
name: codehero
description: Apply independent, risk-focused review perspectives to plans, implementations, diffs, and pull requests. Use when work needs security, reliability, performance, architecture, test-quality, compatibility, operability, or accessibility review, especially as the specialist-review group inside `/rv` or `$rv`. Do not use as the BDD or TDD workflow.
---

# CodeHero Review Perspectives

Review one risk dimension at a time. Use this skill inside the active planning
or review workflow; do not replace that workflow.

## Perspective selection

Run security for code, configuration, CI, dependency, and infrastructure
changes. For prose-only work, mark security not applicable. Select every other
perspective touched by the change:

- **Security:** trust boundaries, attacker-controlled data, authorization,
  secrets, injection, unsafe execution, dependencies, and data exposure.
- **Reliability:** failures, retries, idempotency, concurrency, resource leaks,
  recovery, and destructive edge cases.
- **Performance:** unbounded work, hot paths, query or network amplification,
  memory, and scale assumptions.
- **Architecture:** ownership, coupling, dependency direction, duplicated
  policy, and repository conventions.
- **Tests:** observable behavior, negative paths, test seams, false confidence,
  and missing regression coverage.
- **Compatibility:** APIs, schemas, migrations, persisted data, version skew,
  and rollback safety.
- **Operations:** deployment, observability, alerts, failure diagnosis, and
  rollback.
- **Accessibility:** keyboard, focus, semantics, contrast, and assistive
  technology when user interfaces change.

## Method

1. Resolve the target, fixed point, accepted behavior, and changed surfaces.
2. State which perspectives apply and why; never silently omit security.
3. Run selected perspectives independently so one passing dimension cannot
   hide another failing one.
4. Trace each suspected issue through callers, validation, framework controls,
   configuration, and observable impact before reporting it.
5. Report location, failure or attack scenario, evidence, impact, smallest
   safe fix, and confidence. Keep unverified concerns separate.

Treat findings as hypotheses until reproduced or verified in source. When
called by `$rv`, return findings to it for revision, simplification, and final
validation.
