# Free-tier cloud resources — usage plan for reliability & privacy

**Status:** Proposal (skeleton — judgment marked `TODO(erik)`)
**Date:** 2026-07-02
**Owner:** erik
**Scope:** Map every verified free-tier cloud resource onto fleet needs, biased
toward **reliability** (more failure domains for the things that already exist)
and **privacy** (nothing readable leaves the house). All quotas verified
against official docs 2026-07-01/02 (research session); lowest-confidence items
flagged inline.

## 0. Principles

1. **Free tiers are revocable — never in the critical path.** Everything here
   is a *redundant leg* or an *edge convenience*. The fleet must keep working
   if any provider yanks its free tier tomorrow (Oracle halved A1 in June 2026
   with zero notice; Scaleway/Storj/Railway/Fly free tiers are all dead).
2. **Privacy: ciphertext-only off-prem.** Backups leave the house only
   restic/age-encrypted (provider sees ciphertext + object sizes/timing).
   Metrics mirrors carry *operational* metadata only (series names, values) —
   acceptable; logs mirrors are NOT in scope (log lines leak content).
   Personal/hermes prompt content never routes through third-party
   inference or logging layers; only already-external model traffic may.
3. **One new account max per phase.** Each provider account is attack surface
   (credentials, recovery email, billing). Prefer stacking on accounts we
   already hold (Oracle, Cloudflare, GitHub) before adding new ones.
4. **Blast-domain awareness.** OCI Object Storage/Vault live in the *same
   Oracle account* as voyager — they diversify *service/failure* domains, not
   the account domain. True provider diversity needs a second company (B2/R2).

## 1. Oracle (existing account)

### 1a. Object Storage — 20 GB, S3-compat, WORM-capable

- **Usage:** third crown-jewel leg. Bucket `crown-jewels` (home region
  `sa-saopaulo-1`), versioning + **retention rule** (time-bound WORM — even a
  compromised console session can't delete inside the window; strictly
  stronger than voyager's append-only REST).
- **Wiring:** two new restic jobs on discovery mirroring the `-rest` pair
  (`restic-backups-vault-oci`, `restic-backups-tofu-state-oci`) →
  `s3:<namespace>.compat.objectstorage.sa-saopaulo-1.oraclecloud.com/crown-jewels`.
  Customer Secret Keys (max 2/user) in **sops, not OpenBao** — backup paths
  must survive a sealed vault (proven 2026-07-01). Dead-man textfile metric →
  existing Grafana routing.
- **Privacy:** restic client-side encryption; Oracle sees ciphertext.
- **Reliability:** survives voyager loss + house loss; NOT account loss.
- Gotchas: S3 API = SigV4, path-style; buckets created via S3 API land in the
  root compartment unless the user's designated compartment is set.

### 1b. OCI Vault — 150 secrets free

- **Usage:** third custody domain for the escrow blobs (`age-key.age` 257 B,
  `sops-config.tar.gz`) as base64 secrets. Accessed with Oracle account creds
  only — independent of fleet and house.
- **Never store:** `vault_unseal_key` — would co-locate with the OCI-stored
  OpenBao snapshots (1a), breaking the runbook's separation rule.
- **Privacy:** blobs are already passphrase-age-encrypted; Oracle holds
  double-wrapped ciphertext.

### 1c. APM synthetic monitoring — 10 runs/hr free

- **Usage:** external probe of 1–2 public vhosts from Oracle's vantage →
  OCI Alarm → Notifications (email 1k/mo, or HTTPS → CF Worker reshaping to
  Discord). Partial fix for the "Prometheus on discovery can't report
  discovery's death" SPOF.
- **Note:** likely *superseded by Grafana Cloud synthetics* (§3) which are
  free at 100k API checks/mo with saner alert routing. `TODO(erik)`: pick one
  (running both costs nothing but doubles config surface).

### 1d. Second E2.1.Micro (1 free x86 VM unused)

- **Usage candidates**, ranked:
  1. **Off-prem uptime-kuma + public status page** — complements synthetics
     (history/dashboard vs raw probes), watches all public endpoints.
  2. Restic REST mirror of voyager (weak — same account/region).
  3. Unprovisioned headroom (block budget: voyager ~48 + telstar 47 + micro
     47 ≈ 142 of 200 GB — fits).
- `TODO(erik)`: role. Recommendation: (1).

### 1e. A1 capacity ping-plan (telstar unblock)

- **Phase 1 — probe + alert (build now, no decisions):** systemd timer on
  discovery, 60–90 s jitter, `oci compute compute-capacity-report create`
  for `VM.Standard.A1.Flex 2/12` (single AD in São Paulo). Probes capacity
  **without launching** — no terraform state involved. On `AVAILABLE`:
  Discord webhook (transition-edge only) + textfile gauge
  `oci_a1_capacity_available` for history. OCI CLI + read-scoped API key via
  sops. Caveat: report reflects the overall pool; free-tier launch can still
  fail — trigger, not guarantee.
- **Phase 2 — auto-apply (only if Phase-1 alerts miss the window):**
  discovery runs the `upgrade-retry.sh`-pattern `terragrunt apply` loop on
  AVAILABLE. Needs homelab-iac checkout + OCI env secrets on discovery —
  real state to manage; defer until Phase 1 proves insufficient.
- **Parallel lever — PAYG upgrade** (`TODO(erik)`, the big fork): paid-pool
  capacity priority (the only *reliable* A1 fix), idle-reclamation immunity,
  Object Storage 20→30 GB (per-tier), unlocks the AI-service monthly quotas
  (5 h Speech, 5k tx Vision/Language/DocU). $0 while under limits; risk =
  a real card on an account that can now bill.

### 1f. Rejected on OCI

- Autonomous DB 26ai (vector search real but 1 OCPU + un-tunable vector
  memory — Vectorize/Zilliz beat it), MySQL HeatWave free (vector store
  excluded from free — trap), GenAI service (no free quota), Data Science /
  GPU (none, ever).

## 2. Cloudflare (existing account)

### 2a. Turn on today (zero cost, zero decisions)

- **CT Monitoring** — email alert on any cert issued for our domains. Free
  rogue-issuance detection. Pure win.
- **Turnstile** — 20 widgets, unlimited siteverify. CAPTCHA for any public
  form (telstar projects). Privacy: visitor-side CF JS (already true for
  proxied zones).
- **WAF free**: 5 custom rules + 1 rate-limit rule (10 s window) — geo/path
  blocks in front of the tunnel. Bot Fight Mode **stays off** on API zones
  (all-or-nothing, breaks API clients).

### 2b. AI Gateway (free: caching, rate-limit, analytics)

- **Usage:** front LiteLLM's *external free upstreams only* (Groq, Cerebras,
  Gemini, OpenRouter): response caching, per-provider rate-limit smoothing,
  unified usage analytics.
- **Privacy boundary:** prompts to these providers already leave the house;
  the gateway adds CF as a reader **only if logging is enabled** — and the
  100k persisted-log cap is **total, not monthly**. Policy: logging off (or
  debug-window only); local model traffic (kepler/orion) and hermes personal
  routes **never** pass through it. Langfuse stays the system of record.

### 2c. Telstar edge (rides telstar's timeline)

- **Pages / Workers static assets** — static frontends, free unlimited
  bandwidth, off the reclaimable VM entirely.
- **Workers** (100k req/day, 10 ms CPU) — glue APIs, the Discord-reshaper.
- **Durable Objects** (free since 2025, SQLite, 5 GB) + **Queues** (free
  since 2026-02, 10k ops/day) — small stateful coordination without touching
  home infra.
- **Hyperdrive** (100k queries/day) — only if a Worker must reach a Postgres
  over the tunnel; prefer Nile/Cockroach (§4) so nothing points home.
- Universal SSL covers one subdomain level — keep public hostnames flat.

### 2d. R2 — 10 GB, zero egress (⚠️ card required to activate)

- **Usage:** fourth crown-jewel leg — the **provider-diverse** one (answers
  the Oracle-account blast domain). Same restic `s3:` pattern as 1a. Also
  free static-asset origin for large public files (zero egress).
- `TODO(erik)`: **R2 vs Backblaze B2** (10 GB, no card, free egress to CF,
  native restic `b2:`) as the diverse leg. B2 avoids putting a card on the
  CF account; R2 keeps everything in two accounts. Either satisfies the
  requirement — pick one, don't run both.

### 2e. Workers AI + Vectorize (hermes P6 enabler)

- **Usage:** bge-m3 embeddings (~9.3M tok/day) + Vectorize (30M queried +
  5M stored dims/mo) = complete free semantic-search backend for the hermes
  wiki/P6 "unified approach".
- **Privacy:** wiki content would be embedded **off-prem** — hermes memory is
  personal data. `TODO(erik)`: acceptable, or keep embeddings local (kepler
  runs embedding models already — bge-m3 via llama.cpp is cheap) and use
  Vectorize only for *storage* of vectors (vectors leak less than text, but
  are invertible in principle)? Conservative default: **embed and store
  locally; revisit only if kepler capacity hurts.**
- **Rejected:** Browser Rendering for kindle-dash (10 min/day ≈ 30–60
  screenshots — too thin; self-hosted pipeline stays).

## 3. Grafana Cloud free — the offsite monitoring mirror

- **Quota:** 10k active series, 50 GB logs, 14-day retention, alerting + IRM,
  100k synthetic API checks/mo, 3 users. Native Prometheus `remote_write` +
  Loki push. No card.
- **Usage (the SPOF fix):** discovery Prometheus `remote_write` of a
  **filtered ~20-series allowlist** (host `up`, backup dead-man gauges,
  `oci_a1_capacity_available`, OpenBao seal probe) → Grafana Cloud alert
  rules fire even when discovery is dead. Synthetics probe the public vhosts
  (replaces 1c). IRM → Discord/email.
- **Privacy:** metric names + numeric values only — operational metadata, no
  content. **Do not** mirror logs (lines leak content) — the 50 GB logs quota
  stays unused by policy.
- **Reliability caveat:** over-quota behavior unstated on the pricing page
  (historically caps, never bills — MEDIUM confidence). The allowlist keeps
  us 3 orders of magnitude under quota.
- **Complement:** Better Stack free (10 uptime monitors + heartbeats + 1
  status page) as an orthogonal outside-in probe — `TODO(erik)`: worth the
  extra account? (Principle 3 says at most one new account per phase; Grafana
  Cloud is the higher-value one.)
- **Avoid:** New Relic as DR sink (over-quota = total platform lockout —
  exactly the failure mode being defended against).

## 4. Free databases (telstar-adjacent; no fleet dependencies)

| Service | Free | Fit | Privacy note |
|---|---|---|---|
| **Nile** (Postgres) | 1 GB, never pauses | telstar app state — nothing stateful on the reclaimable VM | public-project data only |
| **CockroachDB Basic** | 10 GiB + 50M RUs/mo | same, bigger | same |
| **Turso** (SQLite) | 5 GB, 500M reads/mo | read-heavy public apps | same |
| **Zilliz** (vector) | 5 GB ≈ 1M vectors | hermes P6 *if* off-prem vectors accepted (§2e) | vectors invertible in principle |
| Avoid: Qdrant free | 1 GB | — | **deleted after 4 weeks idle** |
| Avoid: ClickHouse Cloud | trial-only | Langfuse stays self-hosted | — |

Traps recorded: MongoDB M0 pauses at 30 d idle; DynamoDB always-free needs a
paid-plan account (free-plan accounts auto-close at 6 months); Azure SQL free
pause-vs-bill choice is irreversible; CloudAMQP deletes idle queues at 28 d;
Upstash Kafka dead; Xata free dead; PlanetScale still none.

## 5. Free inference / GPU (privacy-tiered)

**Tier P0 — personal/hermes/HA-voice content: local only.** kepler/orion
llama.cpp, whisper, piper. No change.

**Tier P1 — already-external, non-personal traffic** (LiteLLM routes that
today hit free API models): add overflow entries —
- Groq: llama-3.3-70b (100k tok/day), **whisper-large-v3 (2k req/day)** as a
  *public/non-personal* STT fallback only (HA voice audio is personal → stays
  local; `TODO(erik)` if a degraded-mode exception is acceptable when kepler
  is down).
- Cerebras gpt-oss-120b (1M tok/day, 5 RPM).
- Gemini Flash — ⚠️ **free tier trains on data**: restrict to fully public
  content or skip. `TODO(erik)`.
- OpenRouter one-time $10 → 1,000 free req/day across the :free pool —
  cheapest breadth unlock. `TODO(erik)` (small real spend).

**Training:** Kaggle ~30 h/wk T4×2 (openwakeword PT-BR runs; training data =
own voice recordings — `TODO(erik)`: acceptable on Kaggle? Alternative: local
GPU is slower but private). Colab free as fallback.

## 6. Opportunistic / apply-and-forget

- **Vultr Free Tier Program** (1 vCPU/512 MB, application + lottery): apply,
  architect nothing around it. If granted → candidate external probe host or
  tiny public relay.
- **Northflank Developer Sandbox** — only free PaaS with explicit always-on
  containers (2 services + 2 cron). Fallback if the second micro (1d) is kept
  as headroom.
- **GitHub Actions (public repos, unlimited)** — already-free cron compute;
  candidate runner for the weekly `restic check` against OCI/R2 legs (creds
  via GH secrets — `TODO(erik)`: acceptable? Conservative: keep checks on
  discovery).

## 7. Phasing

| Phase | Items | Decisions needed |
|---|---|---|
| **0 — now** | CT monitoring on; ping-plan Phase 1; OCI Vault escrow copy; Vultr application | none |
| **1 — DR legs** | OCI bucket (WORM) + 2 restic jobs + dead-man metrics; diverse leg R2-or-B2 | 2d fork |
| **2 — monitoring mirror** | Grafana Cloud account, filtered remote_write allowlist, cloud alert rules, synthetics; retire/skip OCI APM | 1c/§3 forks |
| **3 — telstar edge** | Pages/Workers/Turnstile/DB per project; blocked on A1 capacity (or PAYG) | 1e PAYG fork |
| **4 — AI routing** | AI Gateway + overflow routes; Kaggle wake-word run | §5 privacy forks |

Each phase lands as its own PR with verify gates (restore a file from each new
restic leg; force-fire each new alert; kill -9 test against the probe timer).

## 8. Decision forks (all `TODO(erik)`)

1. **R2 vs B2** as the provider-diverse leg (card-on-CF vs new account).
2. **PAYG upgrade** on Oracle (reliable A1 + reclamation immunity vs card).
3. Second micro role (uptime-kuma vs headroom).
4. OCI APM vs Grafana Cloud synthetics (or both).
5. Better Stack second account: yes/no.
6. hermes embeddings: local-only (default) vs Workers AI off-prem.
7. Gemini free (trains on data): exclude entirely?
8. Groq whisper as degraded-mode voice STT: allowed?
9. OpenRouter $10 unlock: spend it?
10. Kaggle for wake-word training with own-voice data: acceptable?

## 9. Sources

Quotas verified 2026-07-01/02 against official pricing/docs pages (Oracle
Always-Free docs, Cloudflare dev-docs, grafana.com/pricing, provider pricing
pages) via research agents; per-claim URLs live in the session transcripts.
Flagged low-confidence: Grafana Cloud over-quota behavior, CF card-required
flags (inference), Zero Trust seat count (JS-only page), New Relic numbers.
