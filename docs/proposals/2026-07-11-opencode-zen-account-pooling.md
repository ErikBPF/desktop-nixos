# OpenCode Zen account pooling, orchestration & declarative management

**Status:** Proposed (decision scaffold) — 2026-07-11. **Ph1-lite validated
2026-07-11:** free-tier `zen-free`/`zen-free-pickle` routes live on discovery
LiteLLM and wired end-to-end into opencode (§8). Real 2-key pool **rotation** still
pending a 2nd Go account.

> Scaffold for human judgment. The as-built inventory and the plan/vendor facts
> below are **researched** (a read-only recon pass over `servarr/machines/discovery`
> + `desktop-nixos/modules/dev`, and the OpenCode Zen/Go docs + community tooling,
> cited inline). The *rule* choices — how many accounts, which billing posture,
> whether to build the orchestrator/provider now — are **decision gates** ruled by a
> human. This RFC ships **no** config; it maps the option space.

## 1. Motivation

Every cloud-model call from opencode **and** hermes funnels through one LiteLLM
gateway route that carries a **single** upstream credential, `OPENCODE_GO_KEY`
(`servarr/machines/discovery/config/litellm/litellm_config.yaml` — all 6 `zen/go`
routes share it). So the fleet's entire cloud coding capacity is capped by **one**
OpenCode Go account's dollar-value limits: **$12 / 5 h (rolling), $30 / week,
$60 / month**. That single account is both the throughput ceiling and a SPOF.

Goal, in three layers of increasing ambition:

- **A — Pool** N owned accounts behind the gateway so caps add up ("2×", then maybe
  more). Start **N = 2**.
- **B — See** the fleet of accounts: which keys are alive, their age, remaining
  headroom — an inventory/health service.
- **C — Manage** them declaratively (a Terraform provider or equivalent), if the
  vendor surface allows it.

## 2. Current state (researched)

### 2a. As-built gateway (cited)

| Fact | Anchor |
|------|--------|
| LiteLLM gateway runs on **discovery** (not kepler), container `ghcr.io/berriai/litellm:v1.86.0`, `--num_workers 4`, SWAG-only | `servarr/machines/discovery/ai-serving.yml` |
| 6 cloud routes → `https://opencode.ai/zen/go/v1`, **all** `api_key: os.environ/OPENCODE_GO_KEY` (single account) | `.../litellm/litellm_config.yaml` (`kimi-k2-code`, `glm-5`, `qwen3-max`, `minimax-m2`, `mimo`, `mimo-pro`) |
| `router_settings:` **intentionally empty** — no routing_strategy, LB, or fallbacks | `litellm_config.yaml` (`router_settings` block) |
| `general_settings` already wires **Redis** (`redis_host: redis`) + master key | `litellm_config.yaml` |
| Secrets via sops → compose env (`os.environ/<VAR>`), key lives in discovery `.env.sops` | `.../discovery/ai-serving.yml`, `.env.example` |
| Downstream (opencode, hermes) call **logical model names** only; upstream key is invisible to them | `modules/dev/opencode.nix` (litellm provider `baseURL`), `modules/hosts/discovery/hermes-agent.nix` |
| Existing per-*consumer* key minting (virtual keys + budgets + allowlists) | `.../discovery/scripts/mint-litellm-keys.sh` (`hermes`, `pala-note`) |

Consequence: adding upstream accounts is a **gateway-only** change. `model_list`
grows from 1→N deployments per model; nothing downstream moves. The Redis and
multi-worker plumbing pooling needs is **already present**.

### 2b. Plan / vendor facts

- **Go** = flat $10/mo (**$5 first month**), 14 curated models, limits in
  **dollar-value** per rolling window ($12/5h · $30/wk · $60/mo); **one member per
  workspace** may subscribe. If **"Use balance"** is enabled, an exhausted Go
  account **silently falls back to pay-per-request Zen credits** instead of blocking.
  ([Go docs](https://opencode.ai/docs/go/), [pricing/limits](https://www.bitdoze.com/opencode-go-plan/))
- **Zen** (the metered tier behind Go) = pay-per-request; **workspaces are
  currently free during beta**, admins set per-member and per-workspace spend
  limits; auto-reload $20 when balance < $5. **Free tier = 100 requests/day, no
  card, all Zen models at $0** — a *request-count* cap, not the Go $-window; free
  ids incl. `deepseek-v4-flash-free` (heavy reasoner — needs large `max_tokens`) +
  `big-pickle`. **Validated 2026-07-11: `cost:0` end-to-end**, and Zen responses
  carry `prompt_cache_hit/miss_tokens` (partial answer to Q5).
  ([Zen docs](https://opencode.ai/docs/zen/))
- **Community rotation pattern** = *per-request round-robin across multiple API
  keys + auto-failover on rate-limit* — explicitly **load-balancing, not account
  churn** (`kaitranntt/ccs` [#114](https://github.com/kaitranntt/ccs/issues/114)).
  This is the sanctioned "workspace rotation" model, and it is exactly what a
  LiteLLM Router does natively.
- **Management surface (confirmed 2026-07-11):** only **inference** endpoints are
  public — `/zen/v1/responses`, `/zen/v1/messages`, `/zen/v1/chat/completions`,
  `/zen/v1/models`, `/zen/go/v1`. Account/workspace/key administration is
  **web-console only** (`opencode.ai/auth`): **no public REST API**, and the
  **`opencode` CLI has no zen/workspace commands** — `opencode auth` only
  (`list`/`login`/`logout`) manages *local* credentials in
  `~/.local/share/opencode/auth.json`, not server-side workspaces.
- **Workspaces are create-only — no delete exists** (console, API, or CLI):
  [anomalyco/opencode#18653](https://github.com/anomalyco/opencode/issues/18653) is
  an **open** feature request (no workaround). Implication: workspace creation must
  be **deliberate** (dead ones linger forever) — this alone makes the P-churn-29d
  option (§4) untenable regardless of ToS.

The last fact is load-bearing: **Layer C (a Terraform provider) has no clean API to
wrap today.**

## 3. Design

### Layer A — Pooling (the core; do first, N = 2)

Native LiteLLM Router. For each of the 6 Go models, replace the single deployment
with N deployments — identical `model_name` and `api_base`, differing only in key:

```yaml
model_list:
  - model_name: kimi-k2-code
    litellm_params:
      model: openai/kimi-k2.7-code
      api_base: https://opencode.ai/zen/go/v1
      api_key: os.environ/OPENCODE_GO_KEY_1
  - model_name: kimi-k2-code
    litellm_params:
      model: openai/kimi-k2.7-code
      api_base: https://opencode.ai/zen/go/v1
      api_key: os.environ/OPENCODE_GO_KEY_2
  # …repeat the pair for glm-5, qwen3-max, minimax-m2, mimo, mimo-pro

router_settings:               # currently empty
  routing_strategy: simple-shuffle   # or sticky (see G2)
  redis_host: redis
  redis_port: 6379
  allowed_fails: 2
  cooldown_time: 300           # long: $-windows reset in hours, not seconds
  num_retries: 3
  enable_pre_call_checks: true
```

On 429 (or quota block) LiteLLM cools that account's deployment and the next
request routes to a rested one → caps effectively add up. **Downstream unchanged.**

**Gotchas (must-handle):**

1. **Disable "Use balance" on every Go account.** Otherwise an exhausted account
   returns 200 (silently billing Zen credits) instead of 429 — the pool never
   rotates and you overpay. A hard 429 is the rotation signal.
2. **Dollar-window ≠ TPM/RPM.** Go caps are $/window, not per-minute tokens, so
   `usage-based-routing-v2` mismodels them. Let the **429→cooldown** path drive
   rotation; `simple-shuffle` (even spread) or sticky-drain is the right strategy.
3. **`--num_workers 4` needs Redis in `router_settings`** (not only
   `general_settings`) or each worker cools down independently. Redis is present.
4. **`cooldown_time` long (~300s), not 30s** — an exhausted account stays 429 for
   up to the 5 h window; short cooldown just wastes probe requests.
5. **Cross-model account coupling.** One account's $-window is shared across all its
   models, but LiteLLM cools per `(model, deployment)`; an exhausted account gets
   one wasted probe per model group before all its routes cool. Minor, self-heals.

### Layer B — Orchestration / inventory service

A small service ("**zenwarden**", working name) that answers: *which accounts do we
own, are their keys alive, how old are they, how much headroom is left?* Given there
is **no management API**, it composes three signals it **can** get:

1. **Liveness / validity** — probe `GET /zen/v1/models` (or a 1-token `/responses`)
   with each key on a timer → alive / revoked / rate-limited; capture any
   rate-limit headers Zen returns.
2. **Self-maintained metadata** — a **manifest** (sops or a small state file) that
   records, per key: account label, `created_at`, Go vs Zen, "Use balance" state.
   *We* own this at mint time; it is the only reliable source of **key age**
   (the vendor exposes none via API).
3. **Spend / headroom** — **LiteLLM already tracks per-deployment spend + tokens**
   (langfuse + prometheus success/failure callbacks). Scrape that per
   `OPENCODE_GO_KEY_n` deployment for burn, and infer exhaustion from 429 rate.

Output: Prometheus metrics + a status endpoint + alerts (key older than
X days; account exhausted > Y% of window; key probe failing). Runtime home: a
servarr compose stack on discovery (M1 per the placement RFC), secrets via the same
sops `.env` path as the pooled keys. **Reconcile, don't churn** — its job is
visibility + drift alerts, not signup automation.

### Layer C — Declarative management (Terraform provider?)

**Blocked on a non-existent API (confirmed 2026-07-11).** A real
`terraform-provider-opencode-zen` needs stable CRUD over keys/workspaces/budgets;
Zen exposes **none** — no REST admin API, no CLI commands, and no workspace *delete*
at all (§2b). A provider can't even satisfy Terraform's destroy lifecycle. Options:

- **C1 — Custom Go provider (terraform-plugin-framework).** Only viable by
  reverse-engineering the private console API behind `opencode.ai/auth` — fragile
  (breaks on any console change), unofficial, and ToS-grey. **Not recommended now.**
- **C2 — Generic `restapi`/`http` TF provider** over the same private endpoints —
  same fragility, less code. Still blocked on the API existing.
- **C3 — Manifest-reconcile (recommended interim).** The Layer-B manifest *is* the
  declarative source of truth; zenwarden reconciles/validates it. No provider.
- **C4 — Defer** a true provider until/unless Zen ships a public management API
  (it's beta; "pricing details coming soon" implies the surface will move).

**Recommendation:** C3 now, revisit C1 only if Zen publishes an API. Track as an
open question, not a committed build.

## 4. Billing posture (what sits behind each key)

Pooling (Layer A) is **agnostic** to what each key represents. That's a separate,
human-ruled policy choice:

| Option | Cost | Caps behind each key | Notes / risk |
|--------|------|----------------------|--------------|
| **P-Go** — N Go subs | $10/mo each ($5 first month) | $12/5h·$30/wk·$60/mo each | Flat, predictable, simplest. **Default.** |
| **P-Zen-beta** — free-beta Zen workspaces on free/limited-time models | $0 during beta | per-request (free models = $0) | Sanctioned multi-workspace posture; **evaporates when beta pricing lands**. Good *bonus* capacity, not a foundation. |
| **P-Zen-credits** — metered Zen credits | pay-per-request (auto-reload $20) | soft, spend-limited | Overflow tier when Go windows exhaust; watch auto-reload. |
| **P-churn-29d** — re-signup Go every 29 days to re-trigger the **$5 first-month** intro | ~$5/acct/mo | same Go caps | **Not recommended — see below.** |

**On P-churn-29d (the "29-day rotation"):** this is distinct from the community
load-balance rotation (§2b) — it's serial re-signup to defeat a *new-customer*
discount. Documented here as an option because the RFC judgment is yours, with an
honest risk read:

- **Payoff is small:** $5/acct/mo ≈ $60/yr per account.
- **Brittle by design:** the $5 is new-customer-gated; vendors fingerprint email /
  payment method / device to block exactly this. It becomes an arms-race cron.
- **Blast radius is your whole pool:** a flagged/banned account or payment method can
  take pooled capacity down *mid-rotation*, and the churn requires fresh
  identities/payment methods each cycle.
- **Beta already undercuts it:** free-beta workspaces (P-Zen-beta) give cheap/free
  overflow *without* churn while the beta lasts.

**Recommendation:** **P-Go as the base + P-Zen-beta as free overflow while beta
lasts.** If cost is the driver, the lever is **N** (more steady accounts), not
churning intros. I'll implement pooling for whatever posture you rule; I'd rather not
build a signup-churn cron, and I don't think it earns its risk. Your call to overrule.

## 5. Cost / capacity model

| N | Steady cost/mo (P-Go) | Pooled caps (5h / wk / mo) |
|---|-----------------------|----------------------------|
| 1 (today) | $10 | $12 / $30 / $60 |
| **2 (start)** | **$20** | **$24 / $60 / $120** |
| 3 | $30 | $36 / $90 / $180 |
| 5 | $50 | $60 / $150 / $300 |

Plus free-beta Zen workspace overflow at $0 while the beta runs.

## 6. Risks

- **Secret sprawl / blast radius** — N Go keys now in discovery `.env.sops`; rotate
  via the same flow, edit only through `rtk proxy sops` ([[rtk_sops_truncation]]).
- **ToS on aggregation** — owning N accounts and pooling them privately is far
  greyer-safe than churn, but multi-account aggregation may still bump Zen ToS;
  low risk for personal homelab scale, worth a glance at the terms.
- **Silent-bill trap** — "Use balance" left on = overspend instead of rotation (§3 A1).
- **Provider fragility** — any console-API-based Layer C breaks without warning.
- **Cross-model coupling** — minor wasted probes (§3 A5).

## 7. Decision gates (human-ruled)

- **G1 — N:** start 2; ceiling? (cost vs caps in §5.)
- **G2 — Routing strategy** *(cache-locality is the deciding axis):*
  - **sticky-drain** (`order:` priority) — acct1 serves everything until it 429s,
    then acct2. Cache stays warm within a session by construction; **no dependency
    on Zen supporting prompt caching, no TTL bug.** Only cost: acct2 idle until
    acct1 exhausts (negligible at ~1 user). ***Lean.***
  - **simple-shuffle** — stateless per-request; **thrashes the provider prompt
    cache within a session** (every turn may hit the other account). Do not use bare.
  - **shuffle + `optional_pre_call_checks: ["prompt_caching"]`** — LiteLLM's
    `PromptCachingDeploymentCheck` pins a conversation to the account that cached its
    prefix while shuffling *new* sessions → per-session affinity *and* spread. Best
    under real concurrency, but **contingent on Zen passing prompt caching through**
    (open Q5) and carries a hardcoded 5-min affinity-TTL bug
    ([#28427](https://github.com/BerriAI/litellm/issues/28427)) that only bites on
    long idle gaps. Upgrade path once concurrency + Zen-cache support are confirmed.
    ([LiteLLM Claude-Code cache-routing tutorial](https://docs.litellm.ai/docs/tutorials/claude_code_prompt_cache_routing))
- **G3 — "Use balance":** confirm **off** on every Go account (required for §3 A1).
- **G4 — Zenwarden:** ~~build now~~ **ruled 2026-07-11: after pooling proves out**
  (Ph2). Language (Python vs Go) + servarr-stack-on-discovery home TBD at Ph2.
- **G5 — Management API:** **ruled 2026-07-11: none exists.** No REST admin API, no
  CLI (`opencode auth` = local creds only), console-only, no workspace delete
  (#18653). Layer C reduces to manifest-reconcile; a true provider is off the table
  until opencode ships an admin API.
- **G6 — Terraform provider:** **ruled 2026-07-11: C3 manifest-reconcile** (C1/C2
  blocked — no API; C4 revisit only if opencode ships an admin API).
- **G7 — Billing posture:** **ruled 2026-07-11: P-Go base + P-Zen-beta overflow**
  (no churn).
- **G8 — Secret shape:** `OPENCODE_GO_KEY_1..N` in discovery `.env.sops`, injected
  as compose env (mirror the current single-key wiring).

## 8. Rollout phases

- **Ph0 — Acquire (deterministic console runbook; no automation possible).** Per
  account, since there is no API/CLI (§2b), the reproducible unit is *procedure +
  manifest*:
  1. Distinct email (one member per workspace) → sign in `opencode.ai/auth`.
  2. Create workspace with a **deterministic name** (`pool-01`, `pool-02`, …). ⚠️
     **Un-deletable** — name/create deliberately (#18653).
  3. Subscribe **Go** (or add Zen credits for the free-beta overflow tier).
  4. **Disable "Use balance"** (required — §3 A1).
  5. Optional guardrail: set a workspace/member monthly spend limit.
  6. Mint an API key → record a manifest row:
     `{ label: pool-02, email, tier: go, key_created_at: <YYYY-MM-DD>, use_balance: false }`.
  7. Add the key to discovery `.env.sops` as `OPENCODE_GO_KEY_<n>` (`rtk proxy sops`).
  For the **existing test workspace**: repurpose it as `pool-01` (it can't be deleted)
  rather than stranding it. The manifest (step 6) is the Layer-C declarative source.
- **Ph1-lite — free-tier validation (DONE 2026-07-11).** `zen-free` +
  `zen-free-pickle` routes at `/zen/v1` on the Homelab free workspace
  (`OPENCODE_ZEN_KEY` in discovery `.env.sops`, servarr `6ccd4e9`); validated
  end-to-end via gateway **and** opencode CLI (`cost:0`). Exposed to opencode
  (litellm virtual-key allowlist `/key/update` + `modules/dev/opencode.nix` models).
  Collateral from riding the bump: litellm `1.86→1.91.2` Prisma **P3009** (self-healed)
  + **langfuse-web OOM** (fixed: 2g + `NODE_OPTIONS`). Proves wiring; does **not**
  test 429-rotation (single key, 100/day).
- **Ph1 — Pool (N=2).** Edit `litellm_config.yaml` (§3 Layer A) + add
  `OPENCODE_GO_KEY_2` to discovery `.env.sops` in the servarr repo →
  `just pull-servarr discovery` → `just kick-stack discovery ai-serving` → **verify
  rotation**: drive a burst that trips acct-1's 429 and confirm hop to acct-2 via
  per-deployment spend (langfuse/prometheus). Git-only servarr flow — no host edits.
- **Ph2 — Zenwarden.** Inventory service (§3 Layer B): key-probe + manifest +
  LiteLLM-spend scrape → metrics + alerts.
- **Ph3 — Declarative (deferred).** C3 manifest-reconcile; a true TF provider only if
  G5 finds a stable API.

## 9. Open research questions

1. Does Zen 429 on Go-cap exhaustion, or only soft-degrade? (Determines whether
   cooldown-based rotation fires cleanly — **verify empirically in Ph1**.)
2. Can one account/workspace hold **multiple** keys? (Changes manifest + rotation.)
3. Does the console expose a stable private API for keys/budgets? (Gates Layer C, G5.)
4. Post-beta Zen pricing — when does P-Zen-beta free overflow end?
5. Does Zen/Go **pass provider prompt caching through** (honor `cache_control`,
   report/bill cache-reads cheaper)? Determines (a) whether cache locality even
   stretches the $-cap and (b) whether the `prompt_caching` pre-call check can layer
   on shuffle (G2). If no passthrough, **sticky-drain is strictly correct**. Verify
   empirically in Ph1 (inspect response usage for cache-read fields).

## 10. Sources

[Go docs](https://opencode.ai/docs/go/) · [Zen docs](https://opencode.ai/docs/zen/) ·
[Go limits/pricing](https://www.bitdoze.com/opencode-go-plan/) ·
[ccs #114 (community rotation)](https://github.com/kaitranntt/ccs/issues/114) ·
[LiteLLM routing](https://docs.litellm.ai/docs/routing) ·
[LiteLLM load balancing](https://docs.litellm.ai/docs/proxy/load_balancing)
