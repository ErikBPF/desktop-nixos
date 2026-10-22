# Hermes native LLM wiki (no agentmemory) — PLAN

**Status:** Implemented (deployed 2026-06-27; unattended cron validated
2026-06-29 04:02; audit 2026-07-02). All seven components shipped — `hermes`
branch scaffold, scoped deploy key, declarative clone
(`hermes-wiki-clone.service`), RW mount + ro key in `hermes-oci.nix`, SOUL
directive, `wiki-curator` skill, daily `wiki-consolidate` cron. As-built
record: [`../hermes-llm-wiki.md`](../hermes-llm-wiki.md). Remaining follow-ups
(merge cadence, hard ingest trigger, token budget) are tracked in
[`2026-06-29-hermes-deferred-improvements.md`](../proposals/2026-06-29-hermes-deferred-improvements.md)
P2–P4. **Pivot 2026-06-26:** drop agentmemory for now; hermes
maintains a Karpathy LLM Wiki natively (its own tools, no MCP). Unify with
agentmemory later once the wiki structure is comfortable.
**Supersedes (for now):** `2026-06-25-hermes-agentmemory-integration.md` (parked
for the later "unified approach"; the research there stays valid).

**Supersession (2026-10-21):** GLM-5.2 (`glm-5`) was retired from LiteLLM after
the duplicated wiki cron was fixed; `wiki-consolidate` now runs on
`deepseek-v4.1-flash`.

## Why native-only first
The party grill flagged the agentmemory write-back as the risky part:
multi-writer conflict (Erik + agentmemory export + hermes) on one syncthing+rebase
loop that *already* throws `.sync-conflict` files and silently wedges on abort.
Going native + branch-isolated removes all of it: **one writer (hermes) on a
dedicated `hermes` branch.** Prove the wiki structure works, then unify.

## Base: vault.git `hermes` branch  *(DONE 2026-06-26)*
- `git push origin origin/main:refs/heads/hermes` → remote branch `hermes`
  (`2a332ea`), a copy of `main`. Workstation working tree left on `main`
  (Obsidian + `obsidian-sync` timer untouched).
- `main` = Erik's vault (human). `hermes` = hermes' LLM wiki working branch.
  **No shared-branch contention.** "Unified approach" later = merge/reconcile
  `hermes` → `main`.
- The branch already carries the Karpathy schema (`AGENTS.md`: ingest/query/lint,
  `raw/ wiki/ log/ index.md inbox.md`) — the wiki base is ready.

## Native architecture (no agentmemory, no MCP)
```
hermes (OCI, discovery)
  ├─ reads raw material: its own /opt/data/sessions (conversation history)
  ├─ curates per AGENTS.md → writes wiki/ , updates index.md/log.md
  └─ writes into a RW-mounted clone of vault.git @ hermes branch
                 │
   discovery host clone (branch: hermes)  ──commit+push (host timer)──▶ origin/hermes
                 │  single writer = hermes → no conflict
   review / unify: merge hermes → main when comfortable
```
- **Discovery host clone** of vault.git checked out on `hermes` (e.g.
  `/home/erik/hermes-wiki`); **mounted RW into the hermes container** (whole clone
  dir — single-file mounts break on atomic rename, per the dev grill).
- **Curator = hermes native cron** (glm-5, nightly, deltas-only, capped turns):
  prompt = the `AGENTS.md` ops over recent sessions. No agentmemory tools.
- **Commit/push on the HOST** (a discovery systemd timer, mirroring
  `obsidian-sync` but for the `hermes` branch) → git creds (`github_erikbpf`,
  already on discovery) stay on the host, **not** in the YOLO container.
- **Review/unify:** inspect the `hermes` branch (GitHub / an Obsidian checkout);
  merge to `main` when the structure proves out.

## Open / next (smallest-increment first)
1. **Source of raw material:** hermes' own `/opt/data/sessions` (`.messages`
   only, deltas since last run). Bound the read (sessions embed huge
   system_prompt/tools — strip to user/assistant).
2. **Clone + mount:** discovery clone on `hermes`; RW mount into hermes;
   git creds on host (host-side commit/push timer, not the container).
3. **Curator cron:** native hermes cron (runtime state → seed-on-boot or accept);
   glm-5; AGENTS.md ops; cost-guarded.
4. **Quality gate:** the party's open concern — how do we know the wiki is good
   vs hallucinated? Start by *reviewing the branch by hand* before any auto-merge
   to main; no auto-merge in phase 1.

## Deferred (the later "unified approach")
- agentmemory as the raw-capture + semantic-search layer feeding the wiki
  (full plan in `2026-06-25-hermes-agentmemory-integration.md`).
- Merging `hermes` → `main` once trusted.
