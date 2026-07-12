---
name: tdd-slice
description: Spicyphus per-slice 6-step TDD loop — behavior.md (seed, human) → grounded grill (GLM) → test-contract.md (refine, architect) → red tests (lock, mimo) → green impl (parallel mimo) → seed-integrity review + lessons.md. Use when implementing a slice under an approved RFC. Triggers: "tdd slice", "per-slice loop", "behavior.md", "test-contract", "red then green", "seed-integrity review", "spicyphus loop".
license: MIT
compatibility: opencode
metadata:
  audience: senior-engineers
  workflow: spicyphus
  lineage: spicyphus
---

## When to load

Active when you are implementing one slice of a feature that already has
an approved RFC/ADR/Spec. If the RFC isn't approved yet, draft it first —
the per-slice loop starts ONLY *after* the Spec gate.

Drop if the task is a single-file edit, a hotfix, or routine drafting
(commit body, runbook, message). Those don't need the 6-step.

## The 6 steps (canonical)

1. **Seed — `behavior.md`** (human only, kept never overwritten)
   - Human dumps intent in raw prose. Missing context = empty sections,
     flagged at step 2. Don't refine yet.
   - **Hard gate:** no agent originates this file's body.

2. **Grounded grill** (main agent, GLM, before any refine)
   - Read `behavior.md`. Infer which existing artifacts the seed implicitly
     touches (prior RFCs/ADRs, recent `lessons.md`, related code). Read them.
   - Emit `Q-1..Q-N` each citing a specific seed phrase AND a specific
     linked doc. Generic elicitation in a vacuum doesn't count.
   - Iterate until persona dry. Then — and only then — refine.

3. **`test-contract.md`** (refine `@architect`, human gate)
   - Architect drafts machine-parseable contract from `behavior.md` + grill
     answers. Two registers: humans-why, machines-what/how.
   - Minimal: input examples, invariants, expected outputs, edge cases,
     framework target. No implementation code yet.

4. **Red tests — lock** (`@general` / mimo)
   - General writes tests from `test-contract.md` only. Contract
     underspecified → re-open step 2 (don't rewrite contract silently).
   - Tests must compile AND fail for the right reason (assertion mismatch,
     not infra).
   - Commit red tests as anchor. Behavior is now machine-locked.

5. **Green impl + parallel code** (`@general` / mimo, multiple in parallel)
   - Spawn 1..N `@general` agents in one message, each owning a vertical
     slice of impl. Implement until all red tests pass.
   - Wrong behavioral assumption found → re-open step 2.

6. **Seed-integrity review + `lessons.md`** (`@architect` then human)
   - Architect diffs implementation vs `behavior.md`. Flag drift. No
     "improvement" outside seed scope.
   - Self-improve loop: gap found → fix `test-contract.md` or `behavior.md`,
     re-run red/green. Cap **3 retries** → halt + report blockers.
   - On clean review, human writes `lessons.md` postmortem (new seed, kept).

## Multi-agent dispatch (opencode)

- Step 2 grill: main thread inline (GLM primary)
- Step 3 test-contract: `@architect` (GLM)
- Step 4 red tests: `@general` (mimo)
- Step 5 green impl: spawn multiple `@general` (mimo) in ONE message via
  parallel Task tool calls
- Step 6 review: `@architect` (GLM)

Per-agent model binds in `~/.config/opencode/opencode.json` (HM-managed
via `opencode-flake`); routing convention lives in global AGENTS.md under
"Per-slice TDD mechanics > Multi-model routing".

## Files per slice

- `docs/behaviors/<slice-slug>/behavior.md` — seed, kept, human-only
- `docs/behaviors/<slice-slug>/test-contract.md` — refine, architect
- `docs/behaviors/<slice-slug>/lessons.md` — postmortem, human
- `tests/...` (under repo conventions) — actual test code

If a slice spans multiple repos, behavior.md lives in the leaf repo first
touched; consumer repos cross-reference, don't duplicate.

## Hard gates (do not skip)

- Angry-baboon before grill (1 → 2)
- Grill dry before refine (2 → 3)
- Red tests fail-for-right-reason before green (4 → 5)
- Seed-integrity check before PR (6)
- No AI co-author trailers on commits

## Self-improve cap

3 retries per slice; then halt and report blockers to user. Do not silently
edit the seed to paper over infra failures — re-seed if behavior was wrong,
fix infra if behavior was right.