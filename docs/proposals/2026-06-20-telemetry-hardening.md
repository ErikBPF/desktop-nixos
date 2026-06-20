# Telemetry hardening — security, QoL, devex

**Date:** 2026-06-20
**Status:** Proposal (skeleton — judgment marked `TODO(erik)`)
**Owner:** erik
**Scope:** the existing push-based observability stack (fleet + k3s Alloy →
discovery's Grafana/Loki/Prometheus). NOT the new platform repo — see
[`2026-06-20-cluster-platform-gitops.md`](2026-06-20-cluster-platform-gitops.md).

> Researched against 2025–2026 guidance (Grafana, Prometheus, OTel, Tailscale,
> CNCF/SRE) and cross-checked against our actual config. Headline: the stack is
> already in better shape than generic advice assumes — several "gaps" are
> closed. The list below is only what genuinely pays off for **our** topology.

## 0. Current state (what's already right — don't touch)

Verified in `servarr/machines/discovery/` + `modules/services/alloy.nix`:
- **Loki retention on** — `compactor.retention_enabled: true`, 14d (`336h`),
  schema v13, filesystem delete store. The generic "you'll fill your disk"
  warning does **not** apply.
- **Prometheus retention** — `--storage.tsdb.retention.time=1y`.
- **Phone-home disabled** per-component (Grafana `GF_ANALYTICS_*`, Loki
  `analytics.reporting_enabled:false`, Alloy `--disable-reporting`) — see
  [[grafana_stack_telemetry]].
- **Dashboards-as-code** — Grafana file provisioning, git-committed JSON.
- **Grafana not exposed** — port removed, SWAG-only, root_url set, signup off.
- **Alloy UI bound to localhost** (`127.0.0.1:12345`), not the tailnet.
- **Images version-pinned** (not `:latest`).

## 1. The one genuine defect — Loki label cardinality (S, do first)

`modules/hosts/kepler/k3s-cluster.nix` `alloyConfig` promotes `pod` **and**
`container` to Loki **stream labels** (`target_label = "pod"` / `"container"`).
Pod names are the textbook high-cardinality footgun: every restart / ReplicaSet
hash mints a new stream, bloating the index and shrinking chunks — worst on the
highest-volume source (the cluster).

- **Fix:** keep `namespace` + `app` (and maybe `container`) as labels; move
  `pod` to **structured metadata** (`loki.process` `structured_metadata` stage),
  or drop it as a label and filter at query time. Set
  `allow_structured_metadata: true` explicitly in `loki.yml` (defaults on for
  schema v13).
- Refs: Loki [labels/cardinality](https://grafana.com/docs/loki/latest/get-started/labels/cardinality/),
  [structured-metadata](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/).

## 2. Top 5 highest-value, lowest-regret changes

| # | Change | Effort | File |
|---|---|---|---|
| 1 | **Fix pod/container label cardinality** (§1) | S | `modules/hosts/kepler/k3s-cluster.nix` |
| 2 | **Grafana hardening flags** — `cookie_secure`, `cookie_samesite=strict`, non-default `secret_key`, `disable_gravatar`, `hide_version`, explicit `allow_sign_up=false` | S | `servarr discovery/monitoring.yml` (GF_* env) |
| 3 | **Alerting → ntfy/Telegram + disk-fill rule** (`predict_linear` on `node_filesystem_avail_bytes` covers both Loki vol + Prom TSDB; host Alloy already ships node metrics). Grafana **unified alerting**, NOT standalone Alertmanager | S–M | new `grafana/provisioning/alerting/` |
| 4 | **Prometheus `--storage.tsdb.retention.size` backstop** — time-only can still overrun a small volume on a cardinality spike | S | `servarr discovery/monitoring.yml` |
| 5 | **Import Node Exporter Full (1860)** as committed JSON — host Alloy uses `prometheus.exporter.unix`, names match | S | `grafana/provisioning/dashboards/` |

## 3. Security — verdicts for an already-encrypted default-deny tailnet

| Item | Verdict |
|---|---|
| Grafana hardening flags (§2.2) | **Do** — real gap |
| Prometheus `retention.size` (§2.4) | **Do** — real gap |
| Confirm `GRAFANA_ADMIN_PASSWORD` + any push token flow via `.env.sops` | **Verify** |
| Digest-pin images (`@sha256`) | Nice-to-have (tags already pinned) |
| **basic-auth on push endpoints** | **Optional** — only separates *workload* from *host*; worth it because cluster pods sit on the tailnet and a popped pod could write garbage. Prometheus `--web.config.file` (bcrypt); Alloy `basic_auth{}`. Loki itself can't basic-auth (needs a proxy). |
| **Loki multi-tenancy (`X-Scope-OrgID`)** | **Optional, not security** — the cluster Alloy already sets `external_labels={cluster=…}`, which gives per-source separation without tenancy cost. Adopt only for split *retention*. |
| **mTLS / on-wire TLS for push** | **Skip — over-engineering.** WireGuard already does mutual node auth + encryption; re-encrypting buys nothing. Only real TLS need is browser→Grafana (SWAG already). |
| PII redaction | Reactive `loki.process replace` for known-noisy sources only; 14d retention is the main mitigation |

Refs: [Tailscale security](https://tailscale.com/security),
[Prometheus HTTPS/auth](https://prometheus.io/docs/prometheus/latest/configuration/https/),
[Grafana hardening](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-security-hardening/).

## 4. QoL / operability

- **Cardinality fix** (§1) — the headline.
- **Alloy `labeldrop` hygiene** (S) — drop `pod_template_hash`,
  `controller_revision_hash`, stray `__meta_*` before ingest.
- **Loki ruler for log-based alerting** (S–M) — the cluster ships **logs only**,
  so LogQL rules (ERROR / `CrashLoopBackOff` / OOM) are currently the *only*
  cluster signal. Single-binary: `ring.kvstore.store: inmemory`,
  `alertmanager_url` → Grafana's built-in.
- **Defer k8s dashboards (15757-60, 21742)** — they query `kube_*`/`container_*`
  that don't exist until kube-state-metrics + cAdvisor ship (platform repo, §
  metrics). Importing now = all-empty panels.
- **Skip** recording rules and SLOs/Sloth for now (nothing to precompute; no SLI
  metrics; arbitrates on-call tradeoffs a solo operator doesn't have).

## 5. DevEx

- **Structured logging + `| json`/`| logfmt`** (S–M) — biggest unlock, zero new
  infra. Make SWAG/nginx + anything we own emit JSON.
- **`allow_structured_metadata: true` + `discover_log_levels: true`** (S) —
  prerequisite for Logs Drilldown and the proper home for `pod`/`trace_id`.
- **Logs/Metrics Drilldown apps** (S) — queryless exploration; install the
  plugins (Logs Drilldown wants the structured-metadata work first).
- **Tempo / tracing** — **defer.** Traces need *instrumented apps*; off-the-shelf
  containers emit ~nothing. Keep `trace_id` flowing into logs as structured
  metadata so it's a 30-min change later, not a re-instrumentation project. The
  one candidate worth it eventually: kepler's hermes/LLM stack via OpenLLMetry.
- **Skip** OTLP-ingest rewrite (Alloy already *is* Grafana's OTel distro; adopt
  OTel *semantic conventions* for new telemetry — that's the free win), Perses
  (pre-1.0), Grafonnet (deprecated).

## 6. The over-engineering line (explicit skips)

mTLS on push (WireGuard already), standalone Alertmanager, formal SLOs, full
OTLP migration, Tempo+exemplars without an instrumented app, Perses today,
dashboards-as-code tooling beyond file provisioning, k8s/Loki-mixin dashboards
before cluster metrics exist.

## 7. Decisions — `TODO(erik)`

- §1 cardinality fix — `pod` to structured metadata vs drop-as-label? (recommend
  structured metadata; keep it queryable.)
- §3 basic-auth on push — worth the toil given default-deny tailnet, or rely on
  the ACL? (lean: rely on ACL now; add basic-auth if/when untrusted workloads
  land on the cluster.)
- §4 Loki ruler — adopt now (logs are the only cluster signal) or wait for the
  metrics rollout to give Prometheus alerting instead?
- Sequencing vs the platform repo's metrics rollout (kube-state-metrics +
  cAdvisor) — that unblocks §4's deferred dashboards.

## 8. Verify (per change)

`just dry kepler` for the Alloy change; `just sync-servarr discovery` +
force-recreate for monitoring.yml/Grafana provisioning; then in Grafana: Loki
cardinality (`/loki/api/v1/series` stream count steady across pod restarts),
the disk-fill alert fires on a synthetic threshold, 1860 populated.
