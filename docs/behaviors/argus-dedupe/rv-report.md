# RV report — Argus dedupe plan

Target: `behavior.md`, `decision-map.md`, `argus-dedupe.feature`,
`implementation-plan.md` (revision 1 → 2).
Reviewer: same session, independent passes; findings verified against source
before any edit. No production code, no host access.

## Pass 1 — conformance to the seed

| Finding | Verdict | Disposition |
|---|---|---|
| Seed calls dedupe "across threads"; the docs only ever promise reply-level dedupe | Confirmed | `behavior.md` Destination redefines it explicitly; `decision-map` D1/constraint section states thread reuse is unreachable by a plugin |
| Seed asserts "warnings now repeat 12h" | **Confirmed after correction** — the first pass read a stale local checkout (4h root). Live source now shows 12h at `policies.yaml:16` (homelab-gitops #197) and the Grafana ConfigMap matches | Q4 resolved; no interval change in any slice |
| Seed lists the authenticated webhook route as a live alternative | Partially false — `contactpoints.yaml:8-12` tombstones `argus-webhook-*`; native Discord is the sole path (`fleet-alerting…:218-220`) | Design was rewritten to parse rendered Discord text; webhook path dropped from consideration |
| Seed asks to compare four mechanisms | Met — D1 table with reasons, plus a named fallback | — |
| Seed asks for alert key incl. unit | Met — and corrected: the label is `name`, surfaced only in `summary` (`rules.yaml:1542`), which is why Slice 5 adds it | — |
| Seed's thread counts (497 active, 15 remaining) | **Verified** 2026-10-25 via the Discord active-threads API and recorded in `behavior.md` | Used as baseline context only; no slice claims it as a metric |

## Pass 2 — technical correctness

| Finding | Severity | Disposition |
|---|---|---|
| Draft 1 keyed on `alertname+host` per message. Wrong: `group_by` groups by alertname+datasource (`policies.yaml:12`) and systemd yields one series per unit, so one message mixes hosts/units and caps at 4+2 (`templates.yaml:31-39`) | High | Rewritten to per-instance families + "NEW if any instance is new" |
| Draft 1 treated `resolved` as needing bookkeeping | Medium | Replaced by `StartsAt` as the episode discriminator — a resolved→firing cycle gets a new start, so no bookkeeping is needed and no clock skew matters |
| Draft 1 implied dedupe reduces inference cost | Wrong — `transform_llm_output` runs after the tool loop (`toolcall-leak-guard/__init__.py:9-11`), so Layer O saves output, not input | Cost claim removed; cost explicitly deferred to Layer I (Slice 3, gated) |
| Draft 1 assumed a plugin could reuse the existing thread | Wrong — thread creation precedes dispatch (`hermes-agents.nix:234-238`) | Documented as a hard constraint; upstream handoff named |
| Missing: every `resolved` notification currently starts a full turn (unconditional mention, `templates.yaml:29-35`) | Opportunity | Added as Slice 4 + secondary improvement #2 |
| Untested edge: omitted instances make the verdict approximate | Medium | Explicit `visible subset` marker and a scenario |
| Session/DB fallback path assumes `SessionDB` read-only is safe | Low | Reused verified API from `hermes-agent-runtime.py:96-126`; read-only open already proven non-mutating there |

## Pass 3 — security (untrusted payload, plugin surface)

| Finding | Disposition |
|---|---|
| Suppression is a denial-of-signal primitive an untrusted summary could trigger | **Design changed to annotate-only.** No code path returns `NO_REPLY` from dedupe, so forging a key can at worst mislabel one line |
| Forged `key` token inside `summary` could shadow the real one | Token fields sanitized to `[A-Za-z0-9._:/-]{1,64}`; only the **last** token on the line is honoured (template emits it last); a forged token in prose produces a different family, never a match; scenario `@adversarial-key` grades it |
| Plugin grants capability | None: no network, no subprocess, no tool, no config write. It reads one file and prepends text. The zero-tool boundary (`hermes-agents.nix:221-225`, asserted by `test_argus.py:20-27`) is untouched |
| Plugin could silence via empty string | Hook returns `None` or an annotated string only — never `""` and never `NO_REPLY`; graded by `@plugin-failure` |
| Ledger tampering by the agent | Impossible — the agent has no tools; the ledger is written only by the plugin process |
| Mount is writable and could rewrite plugin code | Mount is `:ro` from the Nix store, same as `hermes-agents.nix:202`; a config assertion grades it |
| Ledger path traversal / symlink | Fixed absolute path from config; created `0700`-style directory; no user-controlled path component |
| Restart durability vs. secret exposure | Ledger holds alert families, hosts, timestamps and thread ids only — no payload values, no credentials. Values in summaries are not persisted |

## Pass 4 — adversarial (what breaks first)

- *Probe finds no inbound context.* Covered: explicit D1 fallback + Slice 0 stop
  condition. This is the single most likely failure and it is bounded.
- *Message template changes upstream* (someone edits `templates.yaml`). Prose
  fallback masks it until Slice 5's token is the contract; the token is additive,
  so the parse degrades rather than breaks.
- *Ledger and reality diverge after a long mute.* Families expire at 30 days →
  first post-mute alert reads as NEW. Correct bias.
- *Two identical alerts seconds apart, both before the first reply.* Both are new
  on read; the second turn is a repeat. Acceptable: worst case one extra
  investigation, no lost alert.
- *Clock.* Episode identity is Grafana's `StartsAt`, not wall clock — no skew
  sensitivity. Ledger TTL uses plugin clock only for pruning.

## Pass 5 — simplicity (Ponytail)

Removed from draft 1: a separate pure-logic module (logic stays in
`__init__.py`, matching `toolcall-leak-guard`), a `tests/argus-dedupe/` directory
plus a new test framework (the plugin's own `selftest.py` is the seam), a
`stats` subcommand, a config knob per field (only `ALERT_DEDUPE_MODE` and
`ALERT_DEDUPE_LEDGER` remain), a SQLite ledger (one JSON file, atomic rename),
and a metric dashboard (one printed rate). Net: 3 new files in desktop-nixos,
1 edited template in homelab-gitops.

## Validation performed

Static only: every citation re-read in `desktop-nixos` and `homelab-gitops`
after the rewrite; `.gitignore:78` and `.graphifyignore:1` confirmed.
**Not** validated: container hook kwargs, template render —
all listed as Slice 0/5 gates or open questions. No `.feature` scenario is
claimed as passing; the file is marked `@unautomated` until its binding prints
its marker.

## Remaining risks

1. Hook context unavailable → fallback path only (highest likelihood).
2. Ledger/behavior drift after long muting → NEW bias, accepted.
3. Cross-repo ordering: if Slice 5 lands late, prose parsing carries the load and
   is less exact for multi-unit systemd messages.

## Addendum — one-thread-per-alert-type question (2026-10-26)

Evaluated at the human's request; recorded as decision-map D8. The key/ledger is
needed in every variant, and the only variant that reaches a reused thread is an
upstream adapter patch (image build + publish + pin bump + unarchive handling +
migration). Grafana cannot address an existing thread, and giving Argus Discord
tools would break the zero-tool boundary. Chosen design unchanged.
