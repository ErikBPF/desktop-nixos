# Hermes — Deferred Plans (backlog)

**Status:** Backlog (tracked, not scheduled)
**Date:** 2026-06-25
**Parent:** `2026-06-24-hermes-memory-skills.md` (§7 review, §8 OCI cutover)

Work intentionally NOT done in the memory/skills/OCI sessions. Ordered by
value. Each item names its trigger ("do this when …") so nothing here is a
standing obligation.

---

## 1. Memory backbone — `wiki-curator` + Dreaming  *(high value, high effort)*

The Reddit author's #1 unsolved problem and where the LLM-wiki pattern pays off
(proposal §4b/§4e). Upstream flat memory (agent-curated notes) is low-signal
until a curation loop exists.

- **`wiki-curator` skill** — ingest / query / lint a git-tracked, 3-layer
  markdown knowledge base (raw sources → LLM-maintained wiki with
  `[[wikilinks]]` + `index.md`/`log.md` → schema doc). Emits Obsidian-compatible
  markdown (no plugin needed — produce the vault, skip the integration).
- **Dreaming cron** — nightly consolidation: read recent sessions → extract
  decisions/projects/bugs → write into the wiki, auto-loaded at session start.
  - **Use the native scheduler**, not an external systemd timer: the image has
    `cron/scheduler.py` + session hooks (`on_session_start/end/finalize/reset`).
  - **Bound the cost** — "read all conversations" against `/opt/data/sessions`
    on the shared LiteLLM budget can blow up. Cap the window / token budget.
- Memory lives under the `external_dirs` skills tree so it is versioned + shared
  laptop↔gateway.

**Trigger:** after the OCI cutover is stable and Langfuse shows headroom.

## 2. Re-evaluate §1 memory caps against Langfuse  *(cheap, do with #1)*

Caps were raised (10000 / 3000 chars) *before* curation existed — currently
paying ~+4.7k tok/turn for possibly-low-signal auto-notes. Once Dreaming/wiki
produces high-signal memory, measure real tok/turn in Langfuse and lower the
caps if the auto-notes are junk. Baseline + the trace to watch are recorded in
the parent doc §7.

**Trigger:** when #1 lands (caps and curation are coupled).

## 3. rtk skill  *(small — gated on the OCI cutover)*

`hermes-skills/meta/rtk/SKILL.md` — instruct the agent to call `rtk <cmd>` for
supported ops (`git`, `ls`, `grep`, `docker`, `kubectl`, `log`, `json`, `find`,
…). Instruction-based is the ONLY sound integration (proposal §7: `pre_tool_call`
can't rewrite; rtk has no stdin filter; transform hooks would re-exec).

**Trigger:** the moment the OCI cutover puts `rtk` on the container PATH —
NOT before (a skill telling the agent to use a missing `rtk` trips
`tool_loop_guardrails`). Then `just sync-hermes-skills discovery` + recreate.

## 4. Pin the image to a digest  *(hygiene)*

The OCI module runs `nousresearch/hermes-agent:latest`. Under oci-containers
`:latest` is NOT auto-repulled (unlike compose `pull_policy: always`), so a
moving tag gives neither reproducibility nor upgrades. Pin a digest
(`…@sha256:…`) and bump deliberately.

**Trigger:** first deliberate version bump after the cutover settles.

## 5. Re-scope §4d "Feedback Loop"  *(design correction)*

The proposal's §4d ("agent updates its own system prompt") conflicts with the
locked decision that **SOUL stays `:ro`/declarative** (parent §7). If a
self-improvement loop is wanted, it must write a *separate* `learned-*.md` under
the skills/memory tree, never SOUL. Fold into #1 (the wiki is the natural home
for learned facts).

**Trigger:** only if a self-improvement loop is actually desired; otherwise drop.

## 6. §6 community repos — none adopted  *(reference only)*

`0xNyk/awesome-hermes-agent` picks (Mnemosyne, oh-my-hermes, hermes-eval, abvx,
sourcevault) are a reference list, not a plan. The Reddit author's own lesson —
*one file / one job / no deps; self-built beats downloaded; generic integrations
sit unused* — argues against adopting the buffet. Every one is third-party code
in a `YOLO_MODE` + terminal container on the homelab net (parent §6 security
caveat). The `rtk`/`caveman` community-repo claims were already disproven (their
`pre_tool_call`-rewrite mechanism doesn't exist in this image).

**Trigger:** adopt at most ONE, only after the core loop (#1) proves stable, and
only after vetting + pinning the source. `hermes-eval` becomes relevant only
once the skill count justifies regression testing.

---

## Not in scope (explicitly dropped)

- Obsidian *integration* (Hermes Console plugin) — produce an Obsidian-viewable
  vault via #1 instead; skip the plugin (it "sits unused").
- Passive note stores / generic knowledge dumps — invest in the active
  Dreaming+wiki loop, not a store nobody reads.
