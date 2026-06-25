# Hermes memory backbone via agentmemory (git wiki) — PLAN

**Status:** Plan — not deployed. Supersedes deferred-plan §1 (wiki-curator +
Dreaming): we **integrate the already-running agentmemory** instead of building
a curator + nightly cron from scratch.
**Date:** 2026-06-25
**Parent:** `2026-06-24-hermes-memory-skills.md` §9, `2026-06-25-hermes-deferred-plans.md` §1

## TL;DR
Erik already runs **agentmemory** (`rohitg00/agentmemory`) on discovery — a full
memory engine that does embeddings + hybrid search + **automatic 4-tier
consolidation + knowledge-graph extraction + Obsidian export**, with no external
scheduler. The proposal's wiki-curator/Dreaming is *reinventing it*. Plan:
1. Wire **hermes → agentmemory** as an MCP server (`npx -y @agentmemory/mcp`;
   the agent gets save/recall/smart-search/graph tools; agentmemory curates).
2. **Trial both** memory systems (built-in + agentmemory) A/B; disable built-in
   later if agentmemory wins (reclaims the ~10k-char/turn injection then).
3. Deliver the **git wiki** by exporting agentmemory into a discovery-side clone
   of `git@github.com:ErikBPF/vault.git` (scoped subdir) + commit/push timer.

## What's already there (verified on the live container 2026-06-25)
- `discovery/agentmemory:latest`, healthy, on `homelab-net`, REST on `:3111`
  (Bearer `AGENTMEMORY_SECRET`); MCP via the `agentmemory-mcp` stdio CLI.
- Env: `GRAPH_EXTRACTION_ENABLED=true`, `CONSOLIDATION_ENABLED=true`,
  `AGENTMEMORY_INJECT_CONTEXT=true`, `OBSIDIAN_AUTO_EXPORT=true`,
  `AGENTMEMORY_EXPORT_ROOT=/export` → host `/home/erik/backup/Documents/erik/obsidian`
  (`vault/`; **not yet a git repo**).
- The workstation already uses it via `~/.claude.json` mcpServers (CLI
  `agentmemory-mcp`, `AGENTMEMORY_URL=https://memory.homelab.pastelariadev.com`).
- hermes container **has node + npx** (`/usr/local/bin/{node,npx}`) and an
  `mcp_servers` config block → it can run the stdio MCP client.

## Architecture
```
hermes agent (OCI) ──MCP(stdio: agentmemory-mcp)──▶ agentmemory REST :3111
       │                                              │ (homelab-net, internal)
       │ save/recall/smart_search/graph_query         ▼
       └────────── auto consolidation + graph + Obsidian export
                                                      ▼
                              /home/erik/.../obsidian/vault  ──git──▶ git wiki
```

## Components (each a deploy step — NOT done yet)

### 1. hermes → agentmemory MCP (declarative, OCI module `settings`)
- Add to `services.hermes-agent-oci.settings.mcp_servers`:
  ```
  agentmemory = {
    command = "npx"; args = ["-y" "@agentmemory/mcp"];   # or a baked CLI
    env = {
      AGENTMEMORY_URL = "http://agentmemory:3111";        # internal homelab-net
      AGENTMEMORY_SECRET = "\${AGENTMEMORY_SECRET}";       # env indirection
    };
  };
  ```
- **Secret handling**: the rendered config.yaml lives in `/nix/store` (world-
  readable) — the secret MUST NOT be literal there. Add `AGENTMEMORY_SECRET` to
  the hermes sops `server_env` and reference `${AGENTMEMORY_SECRET}` (same
  pattern as `${OPENAI_API_KEY}`; verify hermes expands env in `mcp_servers`).
- **Internal URL** `http://agentmemory:3111` (homelab-net) — not the SWAG URL;
  no TLS/egress in-cluster.
- **npx vs baked**: `npx -y @agentmemory/mcp` fetches from npm on first run
  (egress + latency, then cached in /opt/data). Cleaner: bake/pin the CLI into
  the image or vendor it. Decide (see open questions).
- **MCP stdio vetting**: hermes disables "exfiltration-shaped" MCP stdio entries
  (`config.py` ~5233) — confirm agentmemory passes the allowlist.

### 2. Memory: run BOTH as a trial  *(decision: A/B, do not disable yet)*
- Keep hermes built-in memory (`memory_enabled=true`, caps 10000/3000) **and**
  add agentmemory via MCP. Compare signal before committing to one.
- **Cost during trial is a pure add** (built-in 10k injection stays + agentmemory
  MCP tool defs join the tools array). Accept for the trial; **measure** the
  added tool-token cost from a request dump.
- If agentmemory proves the better store, a later step disables built-in memory
  (the ~10k/turn token win from §9.3) — tracked, not done now.
- If the MCP tool defs are heavy, gate to a minimal subset (save/recall/
  smart_search) via hermes' MCP tool-gating (`config.py` ~2493/2509).

### 3. Git wiki = integrate the existing `git@github.com:ErikBPF/vault.git`  *(decision)*
State: vault.git is cloned on the **workstation** (`~/Documents/erik/obsidian/
vault`); agentmemory on **discovery** exports to a *separate*, non-git path
(`/home/erik/backup/Documents/erik/obsidian/vault`). Bridge them **without
clobbering the hand-curated vault**:
- On discovery, **clone vault.git** to a working dir and point
  `AGENTMEMORY_EXPORT_ROOT` at a **dedicated subdir** of it (e.g.
  `<clone>/agent-memory/`) — agentmemory writes its own `decisions/ lessons/
  errors/ _index.md` tree *under that subdir*, never the vault root. (servarr
  agentmemory config change: repoint `EXPORT_ROOT` + add the clone volume.)
- **Commit + push timer** on discovery (systemd timer / `just` recipe):
  `git add agent-memory/ && commit && pull --rebase && push`. Scope the add to
  the agentmemory subdir so it only touches its own files.
- **Two-writer safety** (Erik's workstation + discovery agentmemory both push to
  vault.git): either (a) discovery commits only its `agent-memory/` subdir +
  pull-rebase before push (low conflict since disjoint paths), or (b) agentmemory
  pushes to a dedicated `agent-memory` **branch** Erik merges. → decide; (a) is
  simpler if the subdir is truly disjoint.
- Mostly a **discovery + servarr** concern (clone + EXPORT_ROOT + timer),
  independent of the hermes module.

## What we DON'T build (cut from deferred §1)
- `wiki-curator` skill — agentmemory's consolidation + obsidian export covers it.
- Dreaming nightly cron — agentmemory consolidates automatically on session
  end / interval. No hermes cron job needed.
- `on_session_start` wiki-load hook — `AGENTMEMORY_INJECT_CONTEXT=true` already
  injects relevant memory; the MCP recall tools cover pull.

## Verification plan (before claiming done)
1. `just dry discovery` green with the new settings.
2. Post-switch: hermes lists the agentmemory MCP tools (`memory_save` etc.);
   MCP handshake OK in logs (no exfil-disable).
3. Round-trip: drive a chat that saves a fact, new session recalls it via
   agentmemory (not built-in memory).
4. agentmemory REST reachable from hermes container
   (`curl -H "Authorization: Bearer …" http://agentmemory:3111/...`).
5. A save produces a markdown file under the vault; the commit timer captures it.
6. Confirm built-in memory injection is gone from the request dump (token drop).

## Rollback
Remove the `mcp_servers.agentmemory` block + re-enable `memory_enabled`;
`just switch-discovery`. Vault git repo is additive (leave or remove). No data
loss — agentmemory state is its own volume.

## 4. Consolidation ownership — move curation to hermes  *(explored 2026-06-25)*

Today **agentmemory owns consolidation**: 4-tier compress + graph extraction +
auto-forget run automatically on `qwen-chat` via litellm (`OPENAI_MODEL=qwen-chat`,
`OPENAI_BASE_URL=http://litellm:4000`). Mechanical, cheap, no agent judgment.

"Move to hermes" = let **hermes' agent** decide what's worth remembering
(spicyphus *humans seed / LLM refines*), driven by a native cron job through the
agentmemory MCP. **Feasibility verified:** cron agents now receive MCP tools
(`discover_mcp_tools()`, #4219); cron jobs pin a model + scope `enabled_toolsets`.

**Design:**
- Disable agentmemory auto-consolidation (`CONSOLIDATION_ENABLED=false`, servarr
  env) — keep it as raw **store + graph + export**; hermes does the curation.
  (Verify what disabling consolidation does to graph/export — they may depend on
  the compress tier; if so, keep agentmemory consolidation and go Hybrid below.)
- **hermes consolidation cron** (native, nightly ~04:00 after session_reset):
  `enabled_toolsets` = agentmemory MCP only; pinned model; prompt = recall recent
  observations → dedupe, extract decisions/lessons/patterns →
  `memory_crystallize` the keepers, `memory_forget` the noise, `memory_save`
  syntheses. agentmemory then graph-extracts + Obsidian-exports the result.
- **Bound cost:** read deltas since last run, not the whole store.

**Trade-offs / open choice:**
- **Full move** (disable agentmemory consolidation; hermes owns it) — one brain,
  judgment-driven; but replaces a tested 4-tier engine, and the cron is runtime
  state (declarative gap: seed-on-boot or accept).
- **Hybrid (recommended)** — keep agentmemory's cheap mechanical consolidation
  (qwen) AND add a hermes periodic *review/crystallize* pass on top (judgment
  where it matters, no engine replacement). Lower risk.
- **Model:** `qwen-chat` (cheap, parity with current) vs `glm-5` (judgment, bills
  the brain budget — only worth it if curation quality clearly improves).

## Decisions (resolved 2026-06-25)
1. **MCP delivery:** `npx -y @agentmemory/mcp` (egress on first run, cached).
2. **Memory:** run BOTH as a trial (A/B); disable built-in later if agentmemory wins.
3. **Git wiki:** integrate `git@github.com:ErikBPF/vault.git` — discovery-side
   clone, agentmemory exports to a scoped subdir, commit/push timer.

## Still open (resolve during build)
- **Two-writer strategy** for vault.git: subdir-scoped pull-rebase push from
  discovery (simple, disjoint paths) vs a dedicated `agent-memory` branch Erik
  merges. Lean subdir-scoped if agentmemory's output is truly namespaced.
- **MCP tool-token budget:** measure the agentmemory tool-def cost from a request
  dump after wiring; gate to save/recall/smart_search if heavy.
- **Secret injection:** verify hermes expands `${VAR}` inside `mcp_servers.env`
  (same as `${OPENAI_API_KEY}`); add `AGENTMEMORY_SECRET` to the hermes sops
  `server_env`. If no expansion, find an alternate path.
- **npm egress:** `npx -y` fetches on first container start — confirm the hermes
  container has outbound npm reach (or pre-warm /opt/data npm cache).
```
