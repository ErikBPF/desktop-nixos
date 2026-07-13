# Discovery stateful workload inventory

**Status:** Audit evidence — observed 2026-07-13 18:56–18:59 -03; P0 migration
tooling and backup ownership remain in progress.

This is evidence, not desired configuration. Re-run P0 inventory tooling before
every mutation. Compose/container state belongs to `servarr`; host orchestration
belongs here. Never infer deletion safety from an unmounted volume alone.

## Baseline identity

- `desktop-nixos`: `b8ac78f36db69cf55087b8890cfc0393b081691a`
- local and discovery `servarr`: `7968d9b4f88b5ede8732c72c6f6ff1073c123c2f`
- discovery deploy branch: `main`
- declared managed Compose units: 13, all active/exited; `sync` is absent
- discovery servarr worktree: tracked files clean, SWAG runtime bind contains
  expected untracked generated state
- active backup containers: `restic-discovery` and `ofelia-discovery`, legacy
  Compose project `homelab`, not a declared systemd-owned `sync` stack

Backup ownership and named-volume coverage are therefore unresolved. P1 must
record and verify its own migration-local snapshot and archive before
recreating SWAG; the P0 fixture proved the reusable mechanism.

## Essential edge state

| Service | Owner | Image ref / image ID | Physical state | Size · owner | Backup status |
|---|---|---|---|---|---|
| SWAG | unit `podman-compose-networking`; project `networking` | `lscr.io/linuxserver/swag:5.6.0-ls467` · `sha256:ce148c3794d2dfcb63eaeed55c516324e800349f8cd57e49ec0eb312fe75f01d` | bind `/home/erik/servarr/machines/discovery/config/swag` → `/config`; no named volume | 20 MiB · `1000:1000` | hourly `/home` Btrfs coverage exists; no migration archive/restore proof |
| AdGuard | unit `podman-compose-networking`; project `networking` | `adguard/adguardhome:v0.108.0-b.83` · `sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927` | bind `config/adguard` → `/opt/adguardhome/conf`; volume `networking_adguard_work` → `/opt/adguardhome/work` | bind 8 KiB · `1000:100`; volume 2,977,366,330 B · `65534:65534`, mode `0700` | no migration archive/restore proof |

`discovery_adguard_work` already exists, is empty, and carries the old
`discovery` project label. This is a P5 name collision, not permission to reuse
or delete it.

## Active named state

| Physical volume | Active consumer | Bytes observed | Class | Canonical target / phase |
|---|---|---:|---|---|
| `ai-serving_langfuse_clickhouse_data` | `langfuse-clickhouse` | 24,030,363,493 | database/control plane | `discovery-langfuse-clickhouse-data` · P7 |
| `ai-serving_langfuse_clickhouse_logs` | `langfuse-clickhouse` | 1,610,056,342 | monitoring/tools | `discovery-langfuse-clickhouse-logs` · P7 |
| `dockhand_dockhand_data` | `dockhand` | 0 | monitoring/tools | `discovery-dockhand-data` · P7 |
| `infra_postgres_data` | `postgres` | 764,930,624 | database/control plane | `discovery-postgres-data` · P7 |
| `infra_redis_data` | `redis` | 17,885,462 | database/control plane | `discovery-redis-data` · P7 |
| `infra_vaultwarden_data` | `vaultwarden`, read-only backup mount | 312,975 | database/control plane | `discovery-vaultwarden-data` · P7 |
| `discovery_kindle_dash_data` | `kindle-dash` | 3,276 | control-plane credentials | `discovery-kindle-dash-data` · P7 |
| `media_gluetun_data` | `gluetun` | 9,943,644 | cache/rebuildable | `discovery-gluetun-data` · P7 |
| `media_recyclarr_data` | `recyclarr` | 0 | media metadata | `discovery-recyclarr-data` · P7 |
| `monitoring_grafana_data` | `grafana` | 54,249,324 | monitoring/tools | `discovery-grafana-data` · P7 |
| `monitoring_healthchecks_data` | `healthchecks` | 340,000 | monitoring/tools | `discovery-healthchecks-data` · P7 |
| `monitoring_prometheus_data` | `prometheus` | 3,998,296,127 | monitoring/tools | `discovery-prometheus-data` · P7 |
| `monitoring_scrutiny_config` | `scrutiny` | 28,670 | monitoring/tools | `discovery-scrutiny-config` · P7 |
| `monitoring_scrutiny_influxdb_data` | `scrutiny-influxdb` | 138,119,409 | monitoring/tools | `discovery-scrutiny-influxdb-data` · P7 |
| `networking_adguard_work` | `adguard` | 2,977,366,330 | essential edge | `discovery-adguard-work` · P2–P5 |
| `tools_changedetection_data` | `changedetection` | 8,726,274 | monitoring/tools | `discovery-changedetection-data` · P7 |
| `tools_stirling_data` | `stirling-pdf` | 0 | cache/rebuildable | `discovery-stirling-data` · P7 |

Compose also declares inactive `memory_agentmemory_data`; live legacy
`discovery_agentmemory_data` is 2,289,000 B and unmounted. Neither is proven
disposable.

## Anonymous and retained state

Active anonymous volumes exist for Flaresolverr, Harbor helper paths, Scrutiny
InfluxDB config, SearXNG cache/config, and the legacy dev Vault file/log paths.
They require owner-specific classification before P7. Numerous zero-link
`discovery_*`, old-project, and 64-hex volumes also exist. Zero links or zero
reported bytes do not prove orphanhood.

Known retained candidate: `kindle-dash_kindle_dash_data`, 193 B, unmounted. It
remains protected until P9 per-resource approval. Known canonical-looking
volumes with zero links are also protected.

## Backup and rollback gaps

- Existing restic jobs cover PostgreSQL dumps, Vaultwarden, and bind-mounted
  app config. They do not cover AdGuard work, ClickHouse, or all monitoring
  volumes.
- `backup-volumes.sh` has no active unit/timer and lacks checksum/read/restore
  proof.
- Latest observed ad-hoc dump:
  `backups/postgres/2026-07-13_183343/litellm.sql.gz`, 183,009,088 B. This is
  not P1/P2 protection.
- P0 proved migration-local snapshot, archive, checksum/read, restore, compare,
  smoke, and rollback-evidence helpers on retained disposable state. Production
  workloads still require an individual ledger and verified backups before
  mutation. Expected downtime remains unmeasured until each ledger is recorded.

## Baseline probes

Before mutation: SWAG `nginx -t` passed; representative Grafana HTTPS returned
200; AdGuard HTTPS returned 302; Kindle LAN HTTP returned a 35,781 B PNG;
wildcard certificate was valid 2026-06-29 through 2026-09-27; fleet rewrite,
external DNS, blocked-domain response, AdGuard 401 auth boundary, and exporter
metrics all behaved as expected.

These results establish comparison evidence only. Repeat exact probes after
every recreate, rollback, and reboot.
