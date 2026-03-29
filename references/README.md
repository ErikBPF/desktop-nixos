# Multi-Machine Homelab

Docker Compose homelab distributed across 4 machines, connected via Tailscale mesh VPN and managed by `just`.

## Hosts

Named after spacecraft, aligned to function.

| Host | LAN IP | Tailscale | OS | Hardware | Role |
|------|--------|-----------|-----|----------|------|
| **Orion** | `192.168.10.220` | `orion` | Bazzite | Ryzen 9 5950X, RX 9070XT 16GB, 64GB RAM | AI inference (day), gaming (night) |
| **Kepler** | — | `kepler` | TrueNAS Scale | Ryzen 5 3600, RTX 3070Ti 8GB, 64GB RAM | NAS + photos + AI usage |
| **Discovery** | `192.168.10.210` | `discovery` | Debian | Intel i5, Quadro P2000, 32GB DDR3 | 24/7 infrastructure, media, monitoring |
| **Voyager** | — | `voyager` | Debian | Minimal | Offsite encrypted backup receiver |

## Machine Configuration & Purpose

### Orion — AI Workstation & Gaming Rig

A gaming and AI inference-oriented machine running Bazzite (immutable Fedora). During the day it runs local LLM models for coding work (currently Qwen 3.5 27B GGUF IQ3_XXS). At night, the AI stack stops and it becomes a Steam gaming machine.

| Component | Spec |
|-----------|------|
| CPU | AMD Ryzen 9 5950X (16C/32T) |
| GPU | AMD RX 9070XT 16GB VRAM |
| RAM | 64GB DDR4 (upgradeable to 128GB) |
| Storage | 500GB NVMe + 2x 500GB SSD |

### Kepler — NAS & Application Server

Primarily a NAS running TrueNAS Scale, but also serves as a compute node for photo management (Immich ML with CUDA), AI usage apps (Open WebUI, n8n), and CI/CD. Plans to evolve into a hypervisor with a virtualized NAS. Storage is managed via ZFS with 7 drives controlled by an LSI 9300 HBA.

| Component | Spec |
|-----------|------|
| CPU | AMD Ryzen 5 3600 (6C/12T) |
| GPU | NVIDIA RTX 3070Ti 8GB |
| RAM | 64GB DDR4 (upgradeable to 128GB) |
| Storage | 2x 240GB SSD (boot mirror), 4x 500GB SSD (fast pool), 5x 4TB HDD (bulk pool) |

### Discovery — 24/7 Infrastructure Brain

The house brain — a small, always-on Debian machine that must be super stable. Runs all core infrastructure (DNS, reverse proxy, monitoring), the full media acquisition and streaming pipeline, and serves as the entry point for all external traffic via Cloudflare Zero Trust. All data needs parity and backups. GPU handles hardware transcoding for Jellyfin and Plex.

| Component | Spec |
|-----------|------|
| CPU | Intel i5 |
| GPU | NVIDIA Quadro P2000 |
| RAM | 32GB DDR3 (max capacity) |
| Storage | 2x 240GB SSD (OS + app configs), 2x 4TB HDD (media + data) |

### Voyager — Offsite Backup Receiver

Minimal Debian machine at a separate location. Receives encrypted, append-only Restic backups from other machines and Syncthing config sync. Must be low-maintenance and reliable.

## Architecture

```
                        Internet
                           |
                   Cloudflare Zero Trust
                           |
                   Cloudflare Tunnel
                           |
              Discovery (SWAG reverse proxy)
               /           |           \
         Tailscale    Tailscale    Tailscale
          mesh          mesh         mesh
           |             |             |
        Orion         Kepler       Voyager
       (AI chat)    (NAS+AI)     (backups)
```

**Domain:** `pastelariadev.com` — subdomains per service (e.g. `jellyfin.homelab.pastelariadev.com`)
**Auth:** Cloudflare Zero Trust (no self-hosted SSO)
**DNS:** AdGuard on Discovery with wildcard rewrite for LAN access

## Stack Assignment

### Orion (10 services)
| Stack | Services |
|-------|----------|
| ai-models | llama-chat (Qwen 27B, Vulkan), llama-embed (Qwen3-Embedding-0.6B, CPU) |
| hermes-agent | Hermes Agent (Nous Research autonomous AI agent) |
| shared | tailscale, alloy, syncthing, docker-prune, scrutiny-collector, hawser |

### Kepler (25+ services)
| Stack | Services |
|-------|----------|
| infra | postgres, redis, qdrant, minio |
| security | wazuh-indexer, wazuh-manager, wazuh-dashboard, clamav |
| photos | immich-server, immich-ml (CUDA), immich-postgres, immich-redis |
| knowledge | karakeep, meilisearch, chrome |
| cicd | gitlab, gitlab-runner |
| ai-usage | open-webui, n8n, n8n-worker, searxng, mcpo, pipelines |
| ~~orchestration~~ | ~~airflow (5 services), restate~~ *(disabled, enable when needed)* |
| sync | syncthing, restic, restic-offsite, ofelia |
| shared | tailscale, alloy, docker-prune, scrutiny-collector, hawser |

### Discovery (47+ services)
| Stack | Services |
|-------|----------|
| networking | swag (nginx + certbot + fail2ban), adguard |
| infra | postgres, redis, vault, vaultwarden |
| monitoring | prometheus, grafana, loki, mimir, tempo, alloy, uptime-kuma, ntfy, healthchecks, scrutiny, scrutiny-influxdb |
| media | gluetun, qbittorrent, prowlarr, flaresolverr, sonarr, radarr, lidarr, recyclarr, unpackerr, decluttarr, autobrr, seerr |
| media-server | jellyfin (NVENC), jellystat, kometa |
| plex | plex (NVENC), tautulli |
| ai-serving | litellm, langfuse-web, langfuse-worker, langfuse-clickhouse |
| tools | obsidian, excalidraw, it-tools, stirling-pdf, changedetection, cyberchef |
| tunneling | cloudflared, tailscale |
| homepage | homepage |
| dockhand | dockhand |
| renovate | renovate |
| shared | syncthing, docker-prune |

### Voyager (7 services)
| Stack | Services |
|-------|----------|
| offsite | restic-rest (append-only), syncthing |
| shared | tailscale, alloy, docker-prune, scrutiny-collector, hawser |

## Storage

### Kepler (TrueNAS ZFS)

| Pool | Drives | Topology | Usable | Purpose |
|------|--------|----------|--------|---------|
| boot | 2x 240GB SSD | Mirror | ~240GB | TrueNAS OS |
| fast | 4x 500GB SSD | RAIDZ1 | ~1.5TB | Docker, Postgres, app configs, photos |
| bulk | 5x 4TB HDD | RAIDZ1 | ~16TB | NAS storage, git repos |

### Discovery

| Mount | Drives | Purpose |
|-------|--------|---------|
| APPS_PATH (`/opt/homelab/apps`) | SSD | App configs, Postgres data |
| MEDIA_PATH (`/mnt/media`) | HDD | Movies, TV, music, downloads |

## Backup Flow

```
Orion (configs) ──Syncthing──→ Kepler (fast pool)
Discovery (Postgres dumps) ──Syncthing──→ Kepler (fast pool)
Discovery (media configs) ──Restic──→ Voyager (encrypted, append-only)
Kepler (all data) ──Restic──→ Kepler bulk pool (local snapshots)
Kepler (critical) ──Restic──→ Voyager (encrypted, append-only)
```

## AI Models

| Model | Host | GPU | Purpose | Size |
|-------|------|-----|---------|------|
| Qwen 3.5 27B (IQ3_XXS) | Orion | RX 9070XT 16GB (Vulkan) | Chat, coding, reasoning (thinking mode) | ~11GB |
| Qwen3-Embedding-0.6B (Q8_0) | Orion | CPU-only | RAG embeddings | ~0.6GB |

LiteLLM on Discovery routes requests: chat → Orion (daytime) / embed → Orion (CPU, always on).

## Security & Hardening

- **Secrets encryption:** All `.env` files encrypted with SOPS + age. Plaintext never committed to git. Use `just edit-env <host>` to modify secrets.
- **Image pinning:** All Docker images pinned to specific version tags — no `:latest` tags anywhere.
- **No-new-privileges:** `security_opt: no-new-privileges:true` applied globally via YAML anchors on all Discovery services.
- **Resource limits:** Memory and CPU limits on heavy services (Postgres 2GB, Redis 512MB, Jellyfin/Plex 4GB each, ClickHouse 2GB, Langfuse 1GB).
- **Disk monitoring:** Scrutiny SMART health dashboard on Discovery with collectors on all 4 hosts.
- **Multi-host management:** Dockhand on Discovery with Hawser agents on remote hosts for centralized container management.
- **Telemetry parity:** Grafana Alloy on all 4 hosts shipping logs/metrics to Discovery's LGTM stack.
- **Observable cleanup:** docker-prune logs output and sends ntfy notifications on all hosts.

## Quick Reference

```bash
# Deploy
just deploy discovery                # all Discovery stacks
just deploy-stack discovery media    # one stack on Discovery
just deploy-all                      # all hosts in order

# Secrets (SOPS + age)
just edit-env discovery              # edit encrypted .env in $EDITOR
just decrypt-env discovery           # decrypt .env.sops → local .env
just encrypt-env discovery           # encrypt local .env → .env.sops
just push-env discovery              # decrypt + push .env to remote host
just push-env-all                    # push to all hosts

# Monitor
just status discovery                # container states
just logs discovery media            # follow logs
just top discovery                   # live resource usage
just ping-all                        # Tailscale connectivity
just ai-health                       # check AI model endpoints

# Database
just db-shell-discovery              # psql on Discovery Postgres
just db-shell-kepler                 # psql on Kepler Postgres
just db-backup-discovery             # dump Discovery databases
just db-backup-kepler                # dump Kepler databases

# AI Models
just models-download                 # download all models
just models-download-chat            # Qwen 3.5 27B → Orion
just models-download-embed           # Qwen3-Embedding-0.6B → Orion
just models-list-orion               # list models on Orion

# Updates
just update discovery media          # pull + restart one stack
just update-host discovery           # pull + restart all Discovery stacks

# First-time
just first-run discovery             # setup one host
just first-run-all                   # setup all hosts in order
```

See [configurations.md](configurations.md) for the full setup walkthrough.
