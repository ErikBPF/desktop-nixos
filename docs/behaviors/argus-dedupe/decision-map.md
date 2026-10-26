# Decision map — Argus alert dedupe

Status: settled except Q1..Q6 (below). Revision 2 (post first-draft review:
per-instance keys, dormant-webhook correction, no cost claim).

## The constraint that decides everything

A thread is created by the Discord adapter when the mentioning channel message
arrives, **before** the agent turn runs (`hermes-agents.nix:238`). Therefore no
plugin can reuse, merge, or suppress a thread; it can only change what Argus
replies *inside* the thread it was given. True one-thread-per-alert-key is an
upstream pre-dispatch change and is already Proposed elsewhere
(`cleytin-thread-lifecycle.md:70-96`). "Dedupe across threads" is therefore
defined as: *the same alert episode is recognised as the same episode in a new
thread, deterministically, and answered with one line.*

## D1 — Dedupe mechanism

| Option | Verdict |
|---|---|
| **(a) Native plugin + durable ledger** | **CHOSEN.** Precedent and loader already in this repo (`hermes-agents.nix:202,228`; `toolcall-leak-guard`). No tool granted, so `tests/argus-security/test_argus.py:20-27` still passes. Runs in-process: no network, no subprocess. Ledger on `/opt/data` survives restart and image pin bumps. Failure mode is fail-open (unannotated full investigation), never silence. |
| (b) `MEMORY.md` writes | **Rejected, with prior art.** It already records alert occurrences and thread IDs, but the file is stale (last write 2026-08-03), model-curated rather than deterministic, capped at 10 000 chars (`hermes-agents.nix:42-45`), and has no episode/TTL semantics. Self-priming of the agent's own text already burned this system once (`cleytin-triage-regression.md:72-74`). |
| (c) Grafana grouping/repeat tuning only | **Rejected as primary, accepted as complementary.** Cannot tell Argus "you have seen this", cannot key across alertnames, and only scales noise linearly. Blanket silence/threshold tuning is already refused (`fleet-alerting…:225-226`). The 12h warning repeat is live (homelab-gitops #197, `policies.yaml:16`), which lowers the baseline but does not recognise a repeat for the agent. |
| (d) Hermes config or upstream patch | **Deferred, not rejected.** The only path to real thread reuse: compute the key at the auto-thread site and skip creation on a repeat. Needs `hermes-flake` change → image build → digest publish → pin bump (`cleytin-thread-lifecycle.md:94-96`), and overlaps that proposal's Stage 1. Handoff, not duplicate work. |

**Fallback if D2 probe finds no usable inbound context:** (c) + the template key
token (D4) + honest SOUL wording ("likely repeat"), with dedupe recorded as
*not deterministic*. Documented degradation, never a silent one.

## D2 — Where the plugin gets its context (the one open technical fact)

`transform_llm_output` is verified to receive `response_text`
(`tests/hermes-agent-runtime.py:138`) and to run after the tool loop
(`toolcall-leak-guard/__init__.py:9-11`). Whether it also receives session id,
chat id, or inbound message text is **UNVERIFIED** — container inspection was
not possible in this session.

Design is therefore layered, and the probe (Slice 0) selects the variant without
changing observable behavior:

- **Layer O (always available):** output hook prepends the deterministic marker
  from the ledger. Needs the current alert key.
- **Layer I (only if a pre-dispatch/input hook exists):** inject a one-line
  ledger fact into the prompt so the model does not re-investigate. This is the
  only layer that reduces inference cost.
- **Context acquisition order:** hook kwargs → `$HERMES_HOME/state.db` newest
  inbound message for the session (native `SessionDB`, read-only;
  `hermes-agent-runtime.py:96-126` shows the API and a read-only path) → give up
  and return `None` (fail-open).

Layer O with no context acquisition is impossible; that is precisely what the
probe decides.

## D3 — Alert key and episode boundary

Message-level grouping is real: `group_by` is
`[grafana_folder, alertname, datasource_uid]` (`policies.yaml:12`) and the systemd
rule yields one series per failed unit (`rules.yaml:1558`), so one Discord
message carries several hosts/units, capped at 4+2 (`templates.yaml:31-39`).

- **Family key** = `alertname | host-or-instance | datasource_uid | unit(name, if present)`
- **Episode** = `family @ startsAt-unix`
- **Repeat** = same family *and* same `startsAt`. A resolved→firing cycle gets a
  new `StartsAt`, so it is a new episode with no resolution bookkeeping needed.
- **New-episode** = same family, different `startsAt` → count increments, reply
  links the previous thread.
- **Message verdict** = NEW if any instance is new; REPEAT only if every visible
  instance is a repeat. Omitted instances (cap) make the verdict *approximate*;
  the marker says `visible subset` when the omission line is present
  (`templates.yaml:37-39`).
- **Severity is an attribute, not identity** — an escalation must not create a
  second family.
- **Why not `alertname+host` alone:** merges distinct failing units on one host
  (`rules.yaml:1542` puts the unit in `summary` only) and merges rules that share
  a name across datasources. Both would suppress a real new failure.

Machine-readable token added by `homelab-gitops` (D4) makes parsing trivial;
a regex over the current prose is the pre-token fallback only.

## D4 — Homelab-gitops template change (leaf, independent)

Append per-alert `· key <family> @ <startsAt-unix>` and surface the unit label,
plus a total-instance count on the omission line. Rationale: deterministic parse,
removes the 4-instance blind spot from the key, and helps humans. One file, no
routing change, no delivery-path change.

## D5 — Thread lifecycle

| Event | Behavior |
|---|---|
| Repeat in a new thread | One-line marker in the new thread: `repeat #3 · <family> · since <iso>` + prior thread link when known. No re-investigation. |
| New episode | `new episode #4 · <family> · since <iso>` + link to the previous episode's thread. |
| Resolved | Marker `resolved · <family> · since <iso>`, episode closed in the ledger; SOUL already forbids closing/archiving from a resolved event (`hermes-agents.nix:257-258`). No investigation. |
| Mapping lost (restart) | Ledger is a file on `/opt/data` → reloads. Nothing to lose. |
| Ledger unreadable/corrupt | `UNKNOWN` verdict → reply says ledger unavailable, cannot confirm repeat; full investigation proceeds. Never crash the turn. |
| Prior thread deleted/archived | Link omitted or left as-is (archived threads stay readable); count still reported. |
| Thread title | Unchanged. Renaming is upstream behavior and out of scope. |

## D6 — Failure modes

| Failure | Effect | Why acceptable |
|---|---|---|
| Plugin raises | Hook returns `None` → response unchanged | Fail-open, same as `toolcall-leak-guard/__init__.py:17,326-328` |
| Ledger write fails | Marker still emitted from in-memory count; logged | Duplicate annotation at worst |
| Plugin disabled (`ALERT_DEDUPE_MODE=off`) | Today's behavior | One-line kill switch, no redeploy |
| Payload forges a key | Attacker can only make a repeat *look* like a repeat | Marker annotates, never suppresses; new alerts still deliver |
| Ledger grows | Cap: 5 episodes/family, 2000 families, 30-day prune | Bounded file, atomic tmp+rename |

## D7 — Secondary improvements, ranked by value/effort

| # | Improvement | Value | Effort | Verdict |
|---|---|---|---|---|
| 1 | Stable key token + unit label + instance count in the Grafana Discord template | High (enables everything, helps humans) | Very low | Include (Slice 5) |
| 2 | Deterministic resolved handling (every resolve currently starts a wasted thread, `templates.yaml:29-35`) | High | Low | Include (Slice 4) |
| 3 | Ledger-backed repeat marker | High (primary) | Medium | Include (Slices 1-3) |
| 4 | Health check asserts plugin registered + ledger writable | Medium | Low | Include (Slice 4) |
| 5 | Input-side prompt note (cost, not noise) | Medium | Low if hook exists | Include, gated by Slice 0 |
| 6 | Owner/runbook one-liner in the reply | Low-medium | Very low | Fold into the SOUL edit, no slice |
| 7 | Thread reuse / archive | Highest | High, cross-repo + upstream | Hand off to `cleytin-thread-lifecycle` proposal |
| 8 | Memory seeding policy | Low | Medium | Rejected — superseded by the ledger |
| 9 | Model swap for better triage | Unknown | Low | Rejected here — separate concern, no evidence in scope |

## D8 — One open thread per alert type (evaluated 2026-10-26)

Idea: keep a single standing thread per alert family; repeats append to it and a
resolve closes it. Conceptually tidier for a human than 15 reply-level markers,
but it does **not** remove the key or the state store, and every variant that
actually reaches the thread is more work than the plugin.

| Variant | What it costs | Verdict |
|---|---|---|
| **a) Upstream adapter reuse** — look up family → thread before `_auto_create_thread` and reuse it | `hermes-flake` source patch (uv2nix build), image publish, pin bump, adapter tests; the same family/episode ledger from D2/D3; unarchive handling because Discord auto-archives (24 h/3 d/1 w) and posting needs `MANAGE_THREADS`; migration of the 15 existing threads. First alert of a new family still has no thread to reuse. | **Not simpler.** Correct long-term shape, but a separate leaf-first track; it overlaps the still-Proposed `cleytin-thread-lifecycle` work. |
| **b) Grafana posts into a standing thread** via webhook `?thread_id` | Grafana's Discord notifier exposes no `thread_id`; needs a relay or a fork. Adds a service that can silence/reroute alerts. | Rejected. |
| **c) Give Argus Discord tools** to create/reuse/rename threads | Breaks the zero-tool boundary asserted by `tests/argus-security/test_argus.py:20-27`; untrusted alert text would reach tool arguments; still needs the key/ledger and adds wrong-thread failure modes. | Rejected. |
| **d) One static thread for all alerts** (relay or manual webhook URL) | Flattens per-alert separation into one busy thread; still needs a relay. | Rejected here. |

Structural point: Grafana's native Discord post is created in the **parent
channel** before any agent work, and cannot be moved into a thread. So a
standing thread per family would contain Cleytin's replies only; the alert text
stays in the channel unless the reply quotes it. Reply-level markers keep the
reply directly under the alert it describes.

Conclusion: keep plugin + ledger as the increment. Thread-per-family is a
product/lifecycle decision for the upstream track, and is worth revisiting only
if the 12 h repeat baseline still leaves too many threads.

## Open questions (human)

- **Q1** Repeat replies: annotate-only (recommended, cannot hide a real alert) or
  allow full suppression after N identical repeats?
- **Q2** Ledger location `/opt/data/state/alert-dedupe/ledger.json` and retention
  (5 episodes/family, 2000 families, 30 days) acceptable?
- **Q3** Is thread-level dedupe (one thread per key) wanted now — which means
  reviving the upstream track — or is reply-level dedupe the accepted goal?
- **Q4** *(resolved 2026-10-25: warning repeat is 12h in source and in the live
  Grafana ConfigMap; critical 1h, info 12h.)*
- **Q5** Should `resolved` skip investigation even when no matching ledger entry
  exists (no prior firing seen)?
- **Q6** Is `unit` (label `name`) safe to print in the Discord message for all
  rules, or only for the `host-systemd` family?
