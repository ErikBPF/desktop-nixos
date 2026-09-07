# Discovery telemetry identity drill

**Status:** Live identity-loss and recovery proven September 7; notification
recipient confirmation remains pending.

This current procedure supports the
[fleet alerting contract](https://github.com/ErikBPF/homelab/blob/main/docs/proposals/2026-08-28-fleet-alerting-reliability-and-response.md).
The older Compose Loki-stop instructions are superseded. This procedure stops
only Discovery's native `alloy.service`; it does not stop any workload, change
alert expressions, or modify configuration. Discovery logs and metrics are
temporarily withheld, so the window is staffed and independently bounded.

## Preconditions

- The previous Discord test rule is resolved and removed. Notification transport
  counters do not establish a human recipient's receipt.
- Discovery's HA-route/probe deployment has finished; no concurrent activation,
  restart, backup intervention, or telemetry change is planned.
- Grafana's production rule inventory matches the expected revision. The
  identity rule and critical-container rule are healthy; there are no unrelated
  pending alerts. Stop if an existing pending alert could fire during the gap.
- Read-only checks show Alloy and Docker active, with no stop propagation from
  Alloy to workloads. Record container IDs, state, health and start times for
  `swag`, `adguard`, `postgres`, `vault` and `litellm`; never dump their environment.
- Named Discovery container telemetry is present and fresh. Immediately before
  stopping Alloy, host-scraped producer sample timestamps must be at most ten
  seconds old, including `sops_runtime_secrets_ready`,
  `vault_agent_required_renders_ready`,
  `vault_agent_render_last_success_seconds` and `litellm_semantic_ready`.
  Gauge values and scrape timestamps are different; compare the latter for this
  timing gate. Readiness values must already be healthy. The render timestamp
  value is a file mtime, not renderer liveness; unchanged contents do not imply
  failed rendering. The current Vault rule checks readiness count/value.
- Recheck Prometheus `/api/v1/status/flags`: `query.lookback-delta` must be `5m`.
  Recheck Alloy and Grafana versions against the implementation basis below;
  a changed shutdown or no-data policy requires another review.

The active GitOps identity rule triggers after 120 seconds of stale/missing
named container telemetry plus five minutes pending, evaluated each minute.
Discovery's critical-container rule explicitly requires healthy named telemetry.
Other producer-absence rules can begin pending once scraped series expire;
fresh baseline samples and prompt recovery keep this attempt below their
five-minute absence plus five-minute pending window. With samples at most ten
seconds old, the earliest unrelated absence firing is 9m50s after injection.
The watchdog scheduled for 8m30s and 60-second recovery budget leave about twenty
seconds of nominal margin. Its one-second timer accuracy and scheduler delays
mean this is not a guaranteed upper bound. Restore promptly instead of relying
on that margin or extending the blackout to get a notification.

### Implementation basis checked September 7

Discovery runs Alloy **1.17.1**. Its
[scrape component](https://github.com/grafana/alloy/blob/v1.17.1/internal/component/prometheus/scrape/scrape.go#L351)
stops the scrape manager on shutdown. Its pinned
[Prometheus fork](https://github.com/grafana/prometheus/blob/87200e297b57/scrape/scrape.go#L245)
cancels the scrape-pool parent context before stopping loops;
[end-of-run staleness](https://github.com/grafana/prometheus/blob/87200e297b57/scrape/scrape.go#L1448)
returns without stale markers when that parent is cancelled. This is the basis
for using the existing graceful service stop, without changing Alloy settings.

Grafana `/api/health` reports **12.3.1**. Its
[no-data handler](https://github.com/grafana/grafana/blob/v12.3.1/pkg/services/ngalert/state/state.go#L518)
passes `noDataState: Alerting` through the normal alerting transition, which
honors the configured pending period. Live Prometheus reports a five-minute
lookback. These checks support the timing bound; they are not a live drill.
The live September 7 Vault rule and current GitOps source check render readiness
count/value with a five-minute pending period. Recheck the live expressions
after any rollout before reusing this procedure.

## Native rollback and injection

Use the documented Discovery SSH endpoint `ssh -p 2222 erik@discovery`. Before
any stop, capture the current unit properties and create the independent native
rollback on Discovery. The name below is reserved for this single attempt; an
existing unit is a stop condition, not permission to overwrite it.

```sh
ssh -p 2222 erik@discovery 'sudo -n systemctl show alloy.service -p ActiveState -p MainPID -p PropagatesStopTo -p ConsistsOf'
ssh -p 2222 erik@discovery 'sudo -n systemd-run --unit=alloy-identity-rollback-20260907 --on-active=8m30s --timer-property=AccuracySec=1s --collect /run/current-system/sw/bin/systemctl start alloy.service'
ssh -p 2222 erik@discovery 'sudo -n systemctl is-active --quiet alloy-identity-rollback-20260907.timer && sudo -n systemctl show alloy-identity-rollback-20260907.timer -p ActiveState -p NextElapseUSecMonotonic'
```

Only after verifying the rollback timer and rechecking all baseline conditions:

```sh
ssh -p 2222 erik@discovery 'sudo -n systemctl stop alloy.service'
```

Record the UTC stop time. Observe native Grafana evaluation and its Alertmanager
every 15 seconds. Expected incremental outcome: **one**
`container-telemetry-identity-missing` firing instance for Discovery and **zero**
Discovery instances of `container-critical-down`. Confirm workload state and
start times independently while their telemetry is unavailable.

Start Alloy immediately after the expected firing, on any unexpected alert or
workload change, or on loss of observer/control access. The already-armed timer
is scheduled to start it independently 8m30s after timer creation:

```sh
ssh -p 2222 erik@discovery 'sudo -n systemctl start alloy.service && sudo -n systemctl is-active --quiet alloy.service'
```

If the expected firing has not appeared by the deadline, restore anyway and
record an incomplete attempt. Do not extend the window, shorten thresholds,
silence alerts, or manufacture a result.

## Recovery and evidence

Require named container series and healthy host-producer samples within two
scrapes (60 seconds) after Alloy starts. Require unchanged workload IDs/start
times and no new workload failures. Observe the telemetry rule recovering and
the native resolved notification; the existing grouping interval can delay
delivery by five minutes. Record exact firing/resolved times and recipient
confirmation separately from transport counters.

After full recovery, cancel an unelapsed rollback timer; retain its user-free
unit journal and value-free observations. If recovery misses 60 seconds, keep
any unelapsed rollback timer armed, report the incident, and abort subsequent
drills. An already elapsed one-shot timer does not provide recurring recovery.

```sh
ssh -p 2222 erik@discovery 'sudo -n systemctl stop alloy-identity-rollback-20260907.timer'
```

No result in this document closes the separate Loki failure gate. An isolated
clone of its datasource/health rule can test native `DatasourceError` handling,
but cannot prove production Loki outage behavior or the production security
rules' `KeepLast` behavior. That distinction must remain in any later receipt.
The September 7 isolated exercise observed Grafana 12.3.1 emit a native
`DatasourceError` on the first failed evaluation despite `for: 2m`; do not
interpret that setting as a two-minute datasource-error grace. The clone
recovered and was removed; production Loki and its rules were unchanged.

## September 7 live receipt

After the Discovery probe rollout and monitoring annotation update completed,
the baseline had 62 production rules with healthy evaluations, all checked fresh producer
samples healthy, and five healthy unchanged workload containers. Apollo's
existing filesystem forecast warning was retained as the sole firing baseline.

The target-native 8m30s rollback timer was verified before Alloy stopped at
**21:46:33 UTC**. Identity loss entered pending at **21:48:50** and fired at
**21:53:50**. The controller observed that firing at 21:54:05 and immediately
started Alloy; it was active at **21:54:05.813**. Fresh named-container telemetry
and all four healthy producer samples were confirmed at **21:54:33**, within
28 seconds. The five workload IDs, health states and start times matched before,
during and after the gap. No Discovery critical-container or unrelated alert
fired. Several absence rules entered pending after samples
expired; all incidental pending states cleared on their normal evaluation
schedules by **21:57:38**, leaving only the existing Apollo warning.

The identity rule evaluated inactive/healthy at **21:54:50** and its native
Alertmanager instance disappeared. All 62 production rule payload hashes were
unchanged. The rollback timer elapsed at **21:55:02–03** and successfully started
the already-active service; Alloy's active timestamp remained 21:54:05. Both
transient units were then unloaded. The attempted final timer cancellation
found an already-collected unit; it was not a failed recovery.

This proves the scoped collector-failure/workload-loss distinction and recovery.
Recipient confirmation of firing/resolved Discord messages remains separate.
Value-free observations are retained on Endeavour in
`~/.local/state/recovery-observation/alloy-drill-20260907.json` (mode 0600).
