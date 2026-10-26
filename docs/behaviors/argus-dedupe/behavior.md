# Argus/Cleytin deterministic alert dedupe — behavior seed

**Status:** planning; no source change applied
**Stage / revision:** PL first draft / 1
**Owners:** `desktop-nixos` (plugin, config, SOUL, health check),
`homelab-gitops` (Discord message template), `homelab` (evidence record)
**Date:** 2026-10-26

## Human seed (verbatim)

> Improve the Hermes agent "Cleytin" (runtime ID `argus`) that acts as first-line
> alert responder in the homelab Discord. Primary goal: deterministic dedupe of
> repeated Grafana alerts across threads. Secondary goal: identify other
> high-value improvements of the same subsystem.

## Destination

A repeat firing of an already-seen alert produces a deterministic one-line
repeat marker plus a link to the prior occurrence, computed from durable state
rather than model judgement, with no tool granted to the agent and no path that
can hide a genuinely new alert.

## Motivation (grounded)

- Dedupe is prompt-only today: `modules/hosts/discovery/argus-SOUL.md:18-24`
  instructs "Check the channel and your session/memory".
- The owning config already admits this cannot work:
  `modules/hosts/discovery/hermes-agents.nix:234-237` — "Fresh auto-threads skip
  backfill by upstream design, so repeat detection across threads is
  best-effort".
- A session is per thread (one `auto_thread` per mentioning channel message,
  `hermes-agents.nix:238`), so cross-thread recall has no substrate.
- Memory exists but is stale, not empty: `/opt/data/memories/MEMORY.md` is
  2420 bytes, last written 2026-08-03, and its entries are exactly this kind of
  alert record ("1st firing ... thread 1533619556965154937"). The substrate works,
  but it is model-curated (no episode/TTL semantics, no deterministic key) and
  has not advanced in ~12 weeks. `memory.memory_char_limit = 10000`
  (`hermes-agents.nix:42-45`).
- Verified 2026-10-25 through the Discord active-threads API: 497 active threads
  in 17 days (490 #incidents, 7 #security); dominant families iac-drift 136,
  systemd 102, authentik backup 56, argocd 49, nix-cache-builder 43, disk 20,
  k8s replicas 20.

## Grounded evidence (verified this session)

| Claim | Evidence |
|---|---|
| Argus has zero platform toolsets, terminal/kanban disabled | `hermes-agents.nix:221-225`; asserted by `tests/argus-security/test_argus.py:20-27` |
| Plugin loader is a supported extension point here | `hermes-agents.nix:202` mounts `hermes-plugins/toolcall-leak-guard` at `/opt/data/plugins/…`; `:228` `plugins.enabled` |
| Plugin shape is `plugin.yaml` + `register(ctx)` + `ctx.register_hook` | `hermes-plugins/toolcall-leak-guard/plugin.yaml:10-12`, `__init__.py:339-340` |
| `transform_llm_output` fires once per turn, after the tool loop, before delivery | `toolcall-leak-guard/__init__.py:9-11` |
| Hook registry is discoverable/invokable in a disposable container | `tests/hermes-agent-runtime.py:129-139` (`discover_plugins`, `has_hook`, `invoke_hook`) |
| The inbound Discord text is the rendered Grafana template | `homelab-gitops/.../alerting/templates.yaml:10-53`, wired at `contactpoints.yaml:22-23,39-40` |
| Title carries alertname only | `templates.yaml:10-16` |
| Body carries severity, cluster, host/instance, datasource_uid, summary, `since`, optional `ended` | `templates.yaml:18-27` |
| Message caps at 4 firing + 2 resolved, remainder omitted without a count | `templates.yaml:31-39` |
| The Cleytin mention is unconditional, so `resolved` also starts a thread | `templates.yaml:29-35` |
| systemd unit name is only inside `summary` (`$labels.name`), not a surfaced label | `rules.yaml:1542` |
| Active repeat intervals: warning 12h, critical 1h, info 12h | `policies.yaml:16,23,29`; merged in homelab-gitops #197 and confirmed in the live Grafana ConfigMap 2026-10-25 |
| `group_by: [grafana_folder, alertname, datasource_uid]` → one message is a *group*, sometimes many hosts | `policies.yaml:12`; `rules.yaml:1558` returns one series per failed unit |
| Structured webhook route is configured but **dormant** | `hermes-agents.nix:241-262`; `contactpoints.yaml:8-12` deletes `argus-webhook-*`, and only `discord`/`discord-deploys` remain |
| Native Discord is the accepted sole Grafana path | `homelab/docs/proposals/2026-08-28-fleet-alerting-reliability-and-response.md:218-220` |
| True one-thread-per-key needs an upstream change | `homelab/docs/proposals/2026-09-15-cleytin-thread-lifecycle.md:58-66,72-79` |
| Plugin path was already preferred over an image bump for the leak guard | `homelab/docs/proposals/2026-09-14-cleytin-triage-regression.md:125-138` |
| Feature files bind to a runner named in a comment | `docs/behaviors/hermes-agent-runtime.feature:2`; plugin scenarios to `selftest.py` (`hermes-agent-hardening.feature:3-4`) |
| `/worktrees/` is already ignored | `.gitignore:78`, `.graphifyignore:1` |

## Scope

In scope: deterministic repeat/new-episode/resolved classification for Grafana
Discord notifications in `#incidents`; durable ledger; deterministic reply
marker; template key token in `homelab-gitops`; health-check assertions.

Out of scope: thread creation, thread reuse, archival, deletion, locking;
Discord write API; any new tool or toolset for Argus; Grafana rule/threshold
changes; silencing; remediation; `#deploys`/`#security` behavior changes;
model change; image pin change.
