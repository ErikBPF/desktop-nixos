# Hermes native LLM wiki — what was built

**Date:** 2026-06-27 · **Status:** **DEPLOYED + demonstrated.** discovery
recovered; SOUL directive + wiki-curator skill live; an in-turn ingest wrote
`wiki/memory-architecture.md` and pushed `hermes` (`0a978dd`) with no
session-reading (~134k tok — vs 253k for the old batch-read; remainder is the
inherent multi-step agent-loop tax, reducible via fewer steps / disabled_toolsets).
**Plan:** `docs/proposals/2026-06-26-hermes-native-llm-wiki.md`.
**Deferred sibling:** `docs/proposals/2026-06-25-hermes-agentmemory-integration.md`
(agentmemory integration — parked for a later "unified approach").

## What this is
Hermes maintains its own durable, git-versioned **Karpathy LLM wiki** — no
agentmemory, no MCP. It is the *build-tapes* doctrine made concrete: knowledge
that survives session resets. Ingest is **incremental and in-turn** (record
durable facts as a conversation produces them), explicitly **not** a nightly
batch that re-reads raw session logs.

## Why this shape (decisions)
- **No agentmemory (for now).** A party-mode grill flagged the agentmemory
  write-back as the risky part (3 writers — Erik, agentmemory export, hermes — on
  one syncthing+rebase loop that already throws sync-conflicts). Start native +
  branch-isolated; unify later.
- **Dedicated `hermes` branch.** Erik's vault stays on `main`; hermes owns
  `hermes`. **One writer per branch → no contention.** Unify = merge later.
- **Incremental, not batch.** A test "read last 2 sessions" pass cost **~253k
  tokens** — because raw session JSONs are ~75% redundant embedded
  system_prompt+tools, and the agent loop re-sends the growing context every
  step. Lesson: don't feed raw sessions. Ingest from the live conversation
  instead (marginal cost). Any backfill of old history is a one-off, pre-digested.

## Architecture (split roles — 2026-06-28)
Two distinct agent roles so base sessions stay fully capable and consolidation stays cheap:
```
BASE sessions (ALL 31 tools)         DAILY agent: `wiki-consolidate` cron
  · keep built-in memory accurate      · minimal toolset = [terminal] only (~1.9k vs 15.5k tools)
  · RETRIEVE: read /opt/wiki to recall · glm-5, schedule 0 4 * * *, cwd /opt/wiki
  · (optional) drop 1 line to inbox.md · source = /opt/data/memories/{MEMORY,USER}.md (distilled,
  · do NOT consolidate inline            small) — NEVER raw session logs
                                        · promote → wiki/ pages + index + log, lint, commit+push
            \                                /
             \                              /
      /opt/wiki  ──RW bind mount──  /home/erik/hermes-wiki  (clone @ hermes branch)
            │  scoped vault.git deploy key (single writer)
   git@github.com:ErikBPF/vault.git  branch `hermes`
            │  later: review, then merge hermes → main  ("unified approach")
   Erik's vault on `main` (Obsidian + obsidian-sync) — untouched
```

**Why split:** an in-session ingest cost ~134k tokens — because every agent-loop
step re-sends the full ~17k base (15.5k of it the tools array), and ingest took
~8 steps. Moving consolidation to a dedicated cron with `enabled_toolsets=
[terminal]` drops the per-call base by ~13.5k; base sessions keep all tools for
the actual work and only *retrieve*. (Measured: 1 model-call floor = 17.4k full
vs ~3–4k terminal-only.)

## Components (status)

| # | Component | Where | Status |
|---|---|---|---|
| 1 | `hermes` branch (Karpathy scaffold: AGENTS.md, templates/, raw/ wiki/ log/, stubs) | vault.git `hermes` | **DONE** (`d508a10`) |
| 2 | vault.git-scoped **write deploy key** (`hermes-discovery-wiki`) | GitHub repo + discovery `~/hermes-wiki-deploy/` | **DONE** (scoped — can't touch other repos) |
| 3 | Discovery clone @ `hermes`, owned uid 10000, `core.sshCommand` scoped to key | discovery `/home/erik/hermes-wiki` | **DONE** |
| 4 | RW mount `/opt/wiki` + ro key `/opt/wiki-key` | `modules/hosts/discovery/hermes-oci.nix` | **DONE + deployed** earlier |
| 5 | **SOUL directive** — "## Your knowledge wiki" (ingest in-turn, shell-write, push) | `modules/hosts/discovery/homelab-SOUL.md` | **BUILT — deploy pending** |
| 6 | **`wiki-curator` skill** — the how-to (AGENTS.md ops, /opt/wiki, shell-write, git) | `hermes-skills/meta/wiki-curator/` | **BUILT — sync pending** |

Proven on the live agent (before discovery went offline): the agent can write
`/opt/wiki` (via execute_code; `write_file` is guarded for `/opt`) and **push to
`origin/hermes`** with the scoped key. One manual ingest pass produced 2 quality
wiki pages + index/log updates and pushed (`2be5171`).

## How "it's on" works
- **SOUL directive (#5)** is injected every turn → the always-present trigger to
  ingest durable knowledge in-turn.
- **`wiki-curator` skill (#6)** carries the detailed ops, loaded on demand.
- Plumbing (#1–#4) is live. So once #5/#6 deploy, hermes has the standing
  instruction + the means. "Guarantee" = directive present + plumbing live +
  a demonstrated in-turn ingest (verification below). NB: a SOUL directive is a
  *soft* guarantee (the model must follow it); a *hard* deterministic trigger
  (on-session-end hook) is a possible future hardening, not built here.

## Deploy + verify (when discovery is back)
1. `just switch-discovery` (ships SOUL #5 + the mounts).
2. `just sync-hermes-skills discovery` (ships skill #6).
3. Recreate/restart picks up the skill index.
4. **Verify on:** SOUL shows "## Your knowledge wiki"; `wiki-curator` in the
   skill index; `/opt/wiki` mounted RW; deploy key push works.
5. **Demonstrate incremental ingest:** have a normal conversation that reaches a
   durable decision; confirm hermes writes a `wiki/` page + pushes `origin/hermes`
   *without* being told to read sessions.

## Security notes
- Deploy key is **scoped to vault.git** (a GitHub deploy key), not Erik's broad
  key — the YOLO container can push *only* vault.git.
- RW vault mount + YOLO terminal: blast radius is the `hermes` branch (git-
  revertible, isolated from `main`). Tighten to a branch-PR flow if desired.
- API not host-published (`publishPorts=false`); reachable only via homelab-net /
  SWAG. (Note: test the API from inside the container, not host localhost.)

## Current blocker
**discovery is offline** (ARP FAILED from kepler — powered off / NIC / switch /
cable; not a deploy issue: autoUpgrade is `switch`+`allowReboot=false`, so it
leaves the host up). kepler + orion are fine. Deploy of #5/#6 waits on discovery
returning. Recovery is physical (power/console; if a wedged boot, pick a prior
GRUB generation).

## Consolidation cron + declarative bootstrap (2026-06-28)
The whole wiki now survives a reprovision — no manual host state. Module
`modules/hosts/discovery/hermes-wiki.nix` (`discovery-hermes-wiki`):
- **sops** `hermes_wiki/deploy_key` (scoped vault.git deploy key) → host user
  `hermes` (uid 10000), materialized at `/run/secrets/hermes_wiki/deploy_key`.
- **`hermes-wiki-clone.service`** (oneshot, before `docker-hermes-agent`): clone
  `vault.git@hermes` → `/var/lib/hermes-wiki` if absent (else fetch+reset), set
  `core.sshCommand`/identity. (Clone moved off `/home/erik`.)
- **`hermes-wiki-cron-seed.service`** (oneshot, after the agent): idempotently
  (re)create the `wiki-consolidate` cron in-container from a canonical spec, so
  prompt/schedule/toolset edits propagate on every deploy.
- OCI mounts repointed → `/var/lib/hermes-wiki:/opt/wiki:rw` + the sops key.

`wiki-consolidate`: glm-5, `enabled_toolsets=[terminal]`, `0 4 * * *`, cwd
`/opt/wiki`. Sources = `/opt/data/memories/{MEMORY,USER}.md` + `/opt/wiki/inbox.md`
(processed+cleared) — never raw sessions. Posts an ntfy summary; ~one tight pass.
Per-call base ~3–4k (vs 17k base sessions). **Validated** (`a15f5be`: 2 pages,
wikilink self-heal, pushed).

## Dropped / deferred
- agentmemory: **stopped** 2026-06-28 (servarr `memory.yml` retired + de-listed;
  container down). The MCP "unified approach" is deferred — re-enable later.
  NB: the workstation's agentmemory MCP now errors until re-enabled.
- Batch "Dreaming" raw-session-replay → never; consolidation reads distilled
  built-in memory + inbox, not session logs.
- In-turn inline ingest in base sessions → dropped; base sessions retrieve only.
- **Still open:** hermes-skills has no git remote (rsync-only backup); merge
  `hermes` → `main` once trusted; confirm the first *unattended* 04:00 cron fire.
