# Configuration Guide

Step-by-step instructions to bring all four hosts online from bare metal.

## Prerequisites

All hosts need:
- Docker Engine 24+ and Docker Compose v2
- `just` command runner
- SSH access between hosts (configured after Tailscale is up)

Generate secrets ahead of time:
```bash
# 32-char hex (API keys, encryption keys)
openssl rand -hex 16

# 64-char hex (Postgres password, secret keys)
openssl rand -hex 32

# Fernet key for Airflow
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### Secrets Management (SOPS + age)

All `.env` files are encrypted with [SOPS](https://github.com/getsops/sops) using [age](https://github.com/FiloSottile/age) encryption. Plaintext `.env` files are gitignored — only encrypted `.env.sops` files are committed.

**First-time setup (one-time):**

```bash
# Install age (NixOS)
nix-env -iA nixos.age
# Or on Debian/Ubuntu: apt install age

# Generate age keypair (if you don't have one)
age-keygen -o ~/.config/sops/age/keys.txt
# The public key is in .sops.yaml — it's already configured in this repo.
```

**Daily workflow:**

```bash
# Edit secrets in your editor (decrypts → edit → re-encrypts automatically)
just edit-env discovery

# Or: decrypt to local .env, edit manually, re-encrypt
just decrypt-env discovery
# ... edit discovery/.env ...
just encrypt-env discovery

# Push decrypted .env to remote host
just push-env discovery
```

The `.sops.yaml` at the repo root configures which files are encrypted and which age key to use.

---

## Phase 1: Discovery (Infrastructure Server)

Discovery must come up first — everything else depends on it for DNS, reverse proxy, monitoring, and Tailscale coordination.

### 1.1 OS Setup

- Install Debian stable (minimal server, no desktop)
- Ensure Docker and Docker Compose v2 are installed
- Set static LAN IP (all other hosts and LAN devices will point DNS here)

### 1.2 Environment

```bash
cd machines/

# Decrypt the encrypted .env (or create from example for first-time setup)
just decrypt-env discovery
# If no .env.sops exists yet: cp discovery/.env.example discovery/.env
```

Fill in `discovery/.env` (see `.env.example` for all variables):

| Variable | How to get it |
|----------|---------------|
| `POSTGRES_PASSWORD` | `openssl rand -hex 32` |
| `REDIS_PASSWORD` | `openssl rand -hex 32` |
| `VAULTWARDEN_ADMIN_TOKEN` | `openssl rand -base64 48` |
| `GRAFANA_ADMIN_PASSWORD` | Choose a password |
| `HEALTHCHECKS_SECRET_KEY` | `openssl rand -hex 32` |
| `HEALTHCHECKS_SUPERUSER_PASSWORD` | Choose a password |
| `CLOUDFLARE_TUNNEL_TOKEN` | From Cloudflare Zero Trust dashboard → Tunnels → Create |
| `CLOUDFLARE_API_TOKEN` | Cloudflare → My Profile → API Tokens → Create with Zone:DNS:Edit for pastelariadev.com |
| `TAILSCALE_AUTHKEY` | From Tailscale admin → Settings → Keys → Generate auth key |
| `TELEGRAM_BOT_TOKEN` | From @BotFather on Telegram |
| `TELEGRAM_CHAT_ID` | Send a message to your bot, then `curl https://api.telegram.org/bot<TOKEN>/getUpdates` |
| `SCRUTINY_INFLUXDB_TOKEN` | `openssl rand -hex 32` |
| `SCRUTINY_INFLUXDB_PASSWORD` | `openssl rand -hex 16` |

After editing, encrypt and push:
```bash
just encrypt-env discovery
just push-env discovery
```

### 1.3 Tailscale

Discovery's Tailscale node is the first one up. After deploying:

```bash
just deploy-stack discovery tunneling
```

Go to [Tailscale admin console](https://login.tailscale.com/admin/machines) and:
1. Approve the `discovery` machine
2. Enable MagicDNS (Settings → DNS → Enable MagicDNS)
3. Note the Tailscale IP assigned to Discovery (100.x.x.x)

### 1.4 Cloudflare Zero Trust

1. Log in to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Create a tunnel: **Networks → Tunnels → Create**
3. Copy the tunnel token into `CLOUDFLARE_TUNNEL_TOKEN` in `.env`
4. Add public hostname entries for each service:

| Subdomain | Service | URL |
|-----------|---------|-----|
| `jellyfin.homelab.pastelariadev.com` | Jellyfin | `http://swag:443` |
| `sonarr.homelab.pastelariadev.com` | Sonarr | `http://swag:443` |
| `grafana.homelab.pastelariadev.com` | Grafana | `http://swag:443` |
| ... | ... | ... |

All entries point to SWAG — Cloudflare Tunnel connects to SWAG, which then routes to the correct backend via nginx proxy configs.

5. Create access policies under **Access → Applications** for each service (or use a wildcard `*.homelab.pastelariadev.com` policy)

### 1.5 Deploy Discovery

```bash
# Push files and env to Discovery
just sync discovery
just push-env discovery

# First-time setup (creates network, starts infra, provisions DBs, deploys all)
just first-run discovery
```


### 1.6 AdGuard DNS

Access AdGuard at `http://<Discovery_LAN_IP>:8090` and configure:

1. **DNS Rewrites** → Add:
   - `*.homelab.pastelariadev.com` → `<Discovery_LAN_IP>` (e.g. `192.168.1.100`)
   - `pastelariadev.com` → `<Discovery_LAN_IP>`
2. Set all LAN devices and your router to use `<Discovery_LAN_IP>` as DNS server
3. Now `jellyfin.homelab.pastelariadev.com` resolves to Discovery on LAN (skipping Cloudflare), and SWAG routes it to Kepler via Tailscale

### 1.7 SWAG & TLS

SWAG (Secure Web Application Gateway) handles reverse proxying via nginx with automatic Let's Encrypt TLS certificates:
- **Cloudflare DNS-01 challenge** for wildcard certs (`*.homelab.pastelariadev.com`)
- **Fail2ban** built-in for IP banning
- **Nginx proxy configs** at `discovery/config/swag/*.subdomain.conf`

**Cloudflare API Token setup:**
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → My Profile → API Tokens
2. Create a custom token:
   - **Permissions:** Zone → DNS → Edit
   - **Zone Resources:** Include → Specific zone → `pastelariadev.com`
3. Copy the token to `CLOUDFLARE_API_TOKEN` in `.env`

To add a new service:
```
newservice.homelab.pastelariadev.com {
	import common
	reverse_proxy http://{$KEPLER_HOST}:<port>
}
```

### 1.8 Verify Discovery

```bash
just status discovery
bash discovery/scripts/validate-health.sh
```

Expected healthy services: postgres, redis, swag, adguard, grafana, prometheus, loki, uptime-kuma, cloudflared, tailscale, vaultwarden, vault

---

## Phase 2: Kepler (NAS + Applications)

### 2.1 TrueNAS Scale Setup

1. Install TrueNAS Scale (Electric Eel 24.10+)
2. Use the 2x 240GB SSDs as boot mirror (during install)
3. Create ZFS pools in TrueNAS UI:

**Fast pool (SSD):**
- Drives: 4x 500GB SSD
- Layout: RAIDZ1
- Pool name: `fast`
- Enable: lz4 compression, auto-snapshots (hourly)

**Bulk pool (HDD):**
- Drives: 5x 4TB HDD (via LSI 9300 HBA)
- Layout: RAIDZ1
- Pool name: `bulk`
- Enable: lz4 compression, auto-snapshots (daily)

4. Create datasets:
```
fast/docker         # Docker root
fast/postgres       # Postgres data
fast/apps           # App configs
fast/models         # AI model files
fast/photos         # Immich uploads
bulk/media          # Movies, TV, music
bulk/media/downloads
bulk/media/movies
bulk/media/tv
bulk/media/music
bulk/backups        # Restic repo
bulk/backups/restic-repo
bulk/backups/postgres
bulk/backups/configs
bulk/git            # GitLab repos
```

5. Set Docker to use the fast pool: TrueNAS UI → Apps → Settings → Pool → select `fast`
6. Create SMB/NFS shares for `bulk/media` if other LAN devices need access

### 2.2 NVIDIA GPU Setup

TrueNAS Scale should detect the RTX 3070Ti automatically. Verify:
```bash
nvidia-smi
```

If not detected, install the NVIDIA driver via TrueNAS UI → System → Advanced → GPU.

### 2.3 Tailscale

SSH into Kepler and start Tailscale:
```bash
just deploy-stack kepler shared
```

Approve `kepler` in the Tailscale admin console. Verify mesh connectivity:
```bash
just ping-all
```

### 2.4 Environment

```bash
cd kepler/
cp .env.example .env
```

Fill in `.env`:

| Variable | How to get it |
|----------|---------------|
| `POSTGRES_PASSWORD` | `openssl rand -hex 32` (separate from Discovery!) |
| `REDIS_PASSWORD` | `openssl rand -hex 32` |
| `MINIO_ROOT_PASSWORD` | `openssl rand -hex 32` |
| `NORDVPN_USER` / `NORDVPN_PASSWORD` | NordVPN → My Account → Manual Setup → Service credentials |
| `SONARR_API_KEY` | `openssl rand -hex 16` (will be used in config pre-seeding) |
| `RADARR_API_KEY` | `openssl rand -hex 16` |
| `LIDARR_API_KEY` | `openssl rand -hex 16` |
| `LITELLM_MASTER_KEY` | `openssl rand -hex 32` |
| `LANGFUSE_SECRET_KEY` | `openssl rand -hex 32` |
| `LANGFUSE_SALT` | `openssl rand -hex 32` |
| `OPENWEBUI_SECRET_KEY` | `openssl rand -hex 32` |
| `N8N_ENCRYPTION_KEY` | `openssl rand -hex 24` |
| `IMMICH_DB_PASSWORD` | `openssl rand -hex 32` |
| `WAZUH_INDEXER_PASSWORD` | Choose (min 12 chars, uppercase, lowercase, digit, special) |
| `KARAKEEP_SECRET` | `openssl rand -hex 32` |
| `KARAKEEP_MEILI_KEY` | `openssl rand -hex 16` |
| `AIRFLOW_FERNET_KEY` | `python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"` |
| `AIRFLOW_SECRET_KEY` | `openssl rand -hex 32` |
| `RESTIC_PASSWORD` | Strong passphrase (this encrypts ALL backups — store it safely!) |
| `RESTIC_OFFSITE_USER` | `kepler` |
| `RESTIC_OFFSITE_PASSWORD` | Must match Voyager's `RESTIC_REST_PASSWORD` |
| `PLEX_CLAIM` | Fresh token from [plex.tv/claim](https://plex.tv/claim) (valid 4 min) |
| `TAILSCALE_AUTHKEY` | From Tailscale admin |
| `MINIO_ROOT_PASSWORD` | `openssl rand -hex 32` |

### 2.5 Deploy Kepler

```bash
just sync kepler
just push-env kepler
just first-run kepler
```

The setup script will:
1. Create `homelab-net` network
2. Start infra (Postgres, Redis, Qdrant, MinIO, pgAdmin)
3. Provision 17 databases
4. Pre-seed *arr configs (Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent)
5. Start all stacks in dependency order

### 2.6 Post-Deploy Configuration

#### Media Acquisition Stack

**Prowlarr** (`prowlarr.homelab.pastelariadev.com`) — configure first, it syncs to all arr apps:
1. Complete initial setup wizard
2. Add indexers: Indexers → Add → select your torrent sites
3. Add arr apps: Settings → Apps:
   - Sonarr: `http://sonarr:8989`, API key from `.env` `SONARR_API_KEY`
   - Radarr: `http://radarr:7878`, API key from `.env` `RADARR_API_KEY`
   - Lidarr: `http://lidarr:8686`, API key from `.env` `LIDARR_API_KEY`
4. Test sync: indexers should appear in each arr app

**Sonarr** (`sonarr.homelab.pastelariadev.com`):
1. Config pre-seeding has set Postgres connections and API key
2. Settings → Media Management → Root Folder → Add `/media/tv`
3. Settings → Download Clients → Add qBittorrent:
   - Host: `gluetun`, Port: `9080`
   - Category: `sonarr`
4. Settings → Profiles → review quality profiles (Recyclarr will sync TRaSH guides)
5. Add your first TV show to verify the pipeline works

**Radarr** (`radarr.homelab.pastelariadev.com`):
1. Settings → Media Management → Root Folder → Add `/media/movies`
2. Settings → Download Clients → Add qBittorrent:
   - Host: `gluetun`, Port: `9080`
   - Category: `radarr`
3. Add a movie to test

**Lidarr** (`lidarr.homelab.pastelariadev.com`):
1. Settings → Media Management → Root Folder → Add `/media/music`
2. Settings → Download Clients → Add qBittorrent:
   - Host: `gluetun`, Port: `9080`
   - Category: `lidarr`

**qBittorrent** (`qbittorrent.homelab.pastelariadev.com`):
1. Pre-seeded config sets WebUI port 9080 and disables auth for local subnet
2. Settings → Downloads:
   - Default Save Path: `/media/downloads/complete`
   - Incomplete Path: `/media/downloads/incomplete`
3. Settings → BitTorrent → enable DHT, PeX, Local Peer Discovery
4. Verify VPN: Tools → Connection Status should show VPN IP (not your real IP)

**Autobrr** (`autobrr.homelab.pastelariadev.com`):
1. Create admin account on first visit
2. Add IRC networks and channels from your indexers
3. Create filters to match releases and push to arr apps
4. Settings → Download Clients → add qBittorrent and/or arr apps

**Seerr** (`seerr.homelab.pastelariadev.com`):
1. Create admin account
2. Connect to Sonarr/Radarr: Settings → Services:
   - Sonarr: `http://sonarr:8989`, API key
   - Radarr: `http://radarr:7878`, API key
3. Connect to Plex or Jellyfin for library sync

**Recyclarr** — runs automatically on a cron schedule:
```bash
# Preview what Recyclarr would change
just exec kepler recyclarr "recyclarr sync --preview"

# Apply TRaSH Guide quality profiles
just exec kepler recyclarr "recyclarr sync"
```

**Unpackerr** — auto-extracts archives from downloads. Configured via env vars in `.env` — connects to Sonarr/Radarr/Lidarr using their API keys.

**Decluttarr** — removes stalled/failed downloads from qBittorrent queue. Runs automatically.

#### Media Servers

**Jellyfin** (`jellyfin.homelab.pastelariadev.com`):
1. Complete initial setup wizard, create admin account
2. Add media libraries:
   - Movies: `/media/movies`
   - TV Shows: `/media/tv`
   - Music: `/media/music`
3. Hardware transcoding: Dashboard → Playback → Transcoding:
   - Hardware acceleration: NVIDIA NVENC
   - Enable hardware decoding for: H264, HEVC, VP9, AV1
4. Users → create family/friend accounts as needed

**Plex** (`plex.homelab.pastelariadev.com`):
1. Claim server immediately after first start (token valid 4 min)
   - If missed: stop container, delete config, update `PLEX_CLAIM` with fresh token, restart
2. Add libraries pointing to `/media/movies`, `/media/tv`, `/media/music`
3. Settings → Transcoder → Enable hardware acceleration (NVIDIA NVENC)
4. Settings → Remote Access → enable if accessed outside Cloudflare Tunnel

**Tautulli** (`tautulli.homelab.pastelariadev.com`):
1. Connect to Plex: provide Plex URL (`http://<KEPLER_LAN_IP>:32400`) and Plex token

**Jellystat** (`jellystat.homelab.pastelariadev.com`):
1. Connect to Jellyfin: provide URL and API key from Jellyfin dashboard

**Kometa** — one-shot metadata manager. Runs, applies poster art, exits:
```bash
just exec kepler kometa "python3 kometa.py --run"
```

#### Photos

**Immich** (`immich.homelab.pastelariadev.com`):
1. Create admin account on first visit
2. Upload photos via web UI or configure the Immich mobile app
3. ML face recognition runs automatically on NVIDIA GPU
4. External libraries: Settings → Libraries → add `/media/photos` if needed

#### AI Stack

**LiteLLM** (`litellm.homelab.pastelariadev.com`):
- Review `kepler/config/litellm/litellm_config.yaml`
- Chat model → `orion:8503` (daytime only, when Orion is on)
- Embed model → `localhost:8501` (always on, local Kepler)
- Rerank model → `localhost:8502` (always on, local Kepler)
- Health check interval: 300s — auto-detects when Orion comes online/offline

**Open WebUI** (`openwebui.homelab.pastelariadev.com`):
1. Create admin account
2. Models are auto-discovered from LiteLLM at `http://litellm:4000/v1`
3. RAG: Settings → Documents → Vector DB → Qdrant at `http://qdrant:6333`
4. Web search: enabled via SearXNG at `http://searxng:8888`

**n8n** (`n8n.homelab.pastelariadev.com`):
1. Create admin account
2. Create credentials for LiteLLM: HTTP Request node → `http://litellm:4000/v1`
3. Workflows that need the heavy chat model should be scheduled during daytime (Orion hours)

**Langfuse** (`langfuse.homelab.pastelariadev.com`):
1. Create admin account (pre-seeded email/password from `.env`)
2. LiteLLM auto-reports all LLM calls to Langfuse via callbacks
3. View traces, costs, and latency per model

#### Knowledge

**Karakeep** (`karakeep.homelab.pastelariadev.com`):
1. Create account on first visit
2. Install browser extension for one-click bookmarking
3. AI features use LiteLLM: configure `OPENAI_BASE_URL=http://litellm:4000/v1` in `.env`

#### CI/CD

**GitLab** (`gitlab.homelab.pastelariadev.com`):
1. Takes 3-5 minutes to boot — watch: `just logs kepler cicd`
2. Set root password on first visit
3. Register runner:
   ```bash
   just exec kepler gitlab-runner "gitlab-runner register \
     --non-interactive \
     --url http://gitlab:80 \
     --token $GITLAB_RUNNER_TOKEN \
     --executor docker \
     --docker-image alpine:latest"
   ```

#### Orchestration (disabled by default)

Orchestration stack (Airflow + Restate) is commented out of the deploy order. Enable when needed:
```bash
just deploy-stack kepler orchestration
```

#### Security

**Wazuh** (`wazuh.homelab.pastelariadev.com`):
1. Login with admin / `WAZUH_INDEXER_PASSWORD`
2. Deploy Wazuh agents on Discovery, Orion, and Voyager for host-level monitoring
3. Configure alerts: Management → Rules

#### Tools

All tools are accessible at their subdomains and require no configuration:
- `obsidian.homelab.pastelariadev.com` — note-taking
- `excalidraw.homelab.pastelariadev.com` — whiteboard
- `it-tools.homelab.pastelariadev.com` — developer utilities
- `stirling-pdf.homelab.pastelariadev.com` — PDF tools
- `filebrowser.homelab.pastelariadev.com` — web file manager (browse media + configs)
- `changedetection.homelab.pastelariadev.com` — website change monitor (add URLs to watch)
- `cyberchef.homelab.pastelariadev.com` — data encoding/decoding

#### Infrastructure (Kepler-local)

**MinIO** (`minio.homelab.pastelariadev.com`):
1. Login with `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
2. Create buckets as needed (Langfuse uses `langfuse` bucket)

#### Backups

**Restic initialization:**
```bash
# Initialize local backup repo
just exec kepler restic "restic init"

# Initialize offsite repo (after Voyager is up)
just exec kepler restic-offsite "restic init"
```

**Ofelia cron jobs** (pre-configured):
- `02:00` daily — Postgres full backup
- `02:30` daily — Config directory backup
- `03:00` daily — Offsite push to Voyager
- `04:00` Sunday — Restic prune (keep 7 daily, 4 weekly, 3 monthly)

**Syncthing** (`syncthing.homelab.pastelariadev.com`):
1. Open Syncthing on each host and exchange device IDs
2. Share folders:
   - Kepler: `${FAST_POOL}/apps` → Discovery, Orion, Voyager
   - Discovery: config + postgres dumps → Kepler
   - Orion: config → Kepler

### 2.7 Verify Kepler

```bash
just status kepler
bash kepler/scripts/validate-health.sh
```

---

## Phase 3: Orion (AI Workstation)

### 3.1 Bazzite Setup

Bazzite is an immutable Fedora-based OS. Docker/Podman is pre-installed. Verify:
```bash
docker --version
docker compose version
```

### 3.2 AMD ROCm GPU

Verify ROCm access:
```bash
ls /dev/kfd /dev/dri/renderD128
# Both should exist
rocminfo  # Should show the RX 9070XT
```

If `rocminfo` is missing, install ROCm: `sudo dnf install rocm-hip-runtime`

### 3.3 Download Model

Download the Qwen 3.5 27B GGUF model to the models directory:
```bash
sudo mkdir -p /opt/models
# Download from HuggingFace — use your preferred GGUF source
# Example: huggingface-cli download bartowski/Qwen3.5-27B-GGUF --include "qwen3.5-27b-q3_k_s.gguf" --local-dir /opt/models
```

### 3.4 Environment

```bash
cd orion/
cp .env.example .env
```

Fill in `.env`:

| Variable | How to get it |
|----------|---------------|
| `TZ` | `America/Sao_Paulo` |
| `TAILSCALE_AUTHKEY` | From Tailscale admin |
| `LLAMA_CHAT_MODEL` | Filename of GGUF model (e.g. `qwen3.5-27b-q3_k_s.gguf`) |
| `MODELS_PATH` | `/opt/models` |
| `LITELLM_API_KEY` | LiteLLM gateway key (for Hermes Agent) |
| `ANTHROPIC_API_KEY` | From Anthropic dashboard (for Hermes Agent fallback) |

Tune llama.cpp args based on your model:
| Variable | Recommended |
|----------|-------------|
| `LLAMA_ARG_CTX_SIZE` | `32768` (27B model) |
| `LLAMA_ARG_N_GPU_LAYERS` | `99` (offload everything to GPU) |
| `LLAMA_ARG_FLASH_ATTN` | `true` |
| `LLAMA_ARG_PARALLEL` | `2` (concurrent requests) |

### 3.5 Deploy Orion

```bash
just sync orion
just push-env orion
just first-run orion
```

### 3.6 Verify Orion

```bash
just status orion
bash orion/scripts/validate-health.sh

# Test chat model
curl http://localhost:8503/health
```

After Orion is up, LiteLLM on Kepler will detect the chat model via health checks and start routing requests to it.

### 3.7 Night Mode

When you switch to gaming, stop the AI stack:
```bash
just stop-stack orion ai-models
```

LiteLLM on Kepler will detect the health check failure and stop routing chat requests. Embed/rerank (on Kepler) remain available.

Start it again in the morning:
```bash
just deploy-stack orion ai-models
```

---

## Phase 4: Voyager (Offsite Backup)

### 4.1 OS Setup

- Install Debian minimal
- Install Docker and Docker Compose
- Attach backup storage and mount at `/mnt/backups`

### 4.2 Environment

```bash
cd voyager/
cp .env.example .env
```

| Variable | How to get it |
|----------|---------------|
| `TAILSCALE_AUTHKEY` | From Tailscale admin |
| `OFFSITE_BACKUP_PATH` | `/mnt/backups/restic` |
| `OFFSITE_SYNC_PATH` | `/mnt/backups/syncthing` |
| `RESTIC_REST_PASSWORD` | Must match Kepler's `RESTIC_OFFSITE_PASSWORD` |

### 4.3 Deploy Voyager

```bash
just sync voyager
just push-env voyager
just first-run voyager
```

### 4.4 Configure Syncthing

1. Access Syncthing on Voyager at `http://voyager:8384` (via Tailscale)
2. Add Kepler, Discovery, and Orion as remote devices (exchange device IDs)
3. Set all shared folders to **Receive Only** — Voyager never modifies data
4. Shared folders to configure:
   - Kepler → Voyager: `configs`, `postgres-dumps`
   - Discovery → Voyager: `discovery-configs`, `discovery-postgres-dumps`
   - Orion → Voyager: `orion-configs`

### 4.5 Verify Voyager

```bash
just status voyager
bash voyager/scripts/validate-health.sh
```

---

## Phase 5: Cross-Host Verification

After all hosts are up:

### Tailscale Mesh
```bash
just ping-all
# Expected: all 4 hosts reachable
```

### Service Access
Test from a LAN device (with DNS pointing to Discovery):
```bash
curl -I https://jellyfin.homelab.pastelariadev.com  # Should reach Kepler via Discovery SWAG
curl -I https://grafana.homelab.pastelariadev.com   # Should reach Discovery directly
```

### Monitoring
1. Open Grafana at `grafana.homelab.pastelariadev.com`
2. Verify Alloy collectors on all hosts are shipping data:
   - Check Loki → Explore → `{host="kepler"}` for Kepler logs
   - Check Prometheus → Targets for remote scrape targets
3. Set up Uptime Kuma checks for critical services across all hosts

### Backup Chain
```bash
# On Kepler — test local backup
just exec kepler restic "restic backup /config --tag test"
just exec kepler restic "restic snapshots"

# On Kepler — test offsite push (after Voyager is up)
just exec kepler restic-offsite "restic backup /config --tag test-offsite"

# On Voyager — verify backup landed
just exec voyager restic-rest "ls /data/m2/"
```

### Syncthing
Open Syncthing UIs on each host and verify:
- All peers connected
- Folders syncing (green check marks)
- Voyager folders in "Receive Only" mode

---

## Post-Deployment: New Infrastructure Services

After all hosts are up and verified, configure these services added in M001.

### Scrutiny — Disk Health Monitoring

Scrutiny monitors SMART disk health across all hosts. The hub (omnibus) runs on Discovery, collectors on each host.

**Step 1: Enumerate drives on each host**

SSH into each host and list block devices:
```bash
lsblk -d -o NAME,SIZE,MODEL,SERIAL
```

**Step 2: Update compose files**

For each host, edit the compose file and uncomment/update the `devices:` section in the scrutiny service:
- Discovery: `monitoring.yml` → `scrutiny` service
- Kepler: `shared.yml` → `scrutiny-collector` service
- Orion: `shared.yml` → `scrutiny-collector` service
- Voyager: `shared.yml` → `scrutiny-collector` service

Example:
```yaml
devices:
  - /dev/sda
  - /dev/sdb
  - /dev/nvme0n1
```

> **Kepler note:** TrueNAS Scale manages ZFS pools which own raw block devices. Direct device passthrough may conflict with ZFS. Test with one drive first.

**Step 3: Deploy and verify**
```bash
just deploy-stack discovery monitoring
# Wait 30s for startup
curl -sf http://discovery:8080/api/health  # Scrutiny hub health
```

Dashboard: `http://discovery:8080`

### Dockhand — Multi-Host Container Management

Dockhand on Discovery manages containers across all hosts via Hawser agents.

**Step 1: Verify Hawser agents are running**
```bash
for host in kepler orion voyager; do
  curl -sf http://$host:2376/_hawser/health && echo "$host: healthy"
done
```

**Step 2: Configure environments in Dockhand UI**
1. Open Dockhand at `http://discovery:3018`
2. Settings → Environments → Add Environment
3. For each remote host:
   - Name: `kepler` / `orion` / `voyager`
   - Connection: Hawser Standard
   - Host: `kepler` / `orion` / `voyager` (Tailscale hostname)
   - Port: `2376`
   - Token: (from `just decrypt-env <host>` → `HAWSER_TOKEN`)
4. Test connection — should show container count
5. Enable Activity Collection and Metrics Collection per environment

**Step 3: Configure notifications**
1. Settings → Notifications → Add Channel
2. Type: ntfy, URL: `http://ntfy/homelab-alerts`
3. Enable update checking per environment for image update notifications

---

## Maintenance Checklists

### Weekly
- [ ] Check `just status-all` — all services healthy
- [ ] Check Grafana dashboards for anomalies
- [ ] Verify Restic backup snapshots exist on Kepler and Voyager
- [ ] Check Uptime Kuma for any missed pings

### Monthly
- [ ] `just update-host kepler` — pull latest images
- [ ] `just update-host discovery`
- [ ] Review CrowdSec alerts: `just exec discovery crowdsec "cscli alerts list"`
- [ ] Check ZFS pool health on Kepler: `zpool status`
- [ ] Prune old Restic snapshots: `just exec kepler restic "restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune"`
- [ ] Review Wazuh dashboard for security events

### Before TrueNAS Updates
1. Snapshot the boot pool: `zpool snapshot boot-pool@pre-update`
2. Verify all backups are current
3. Stop all stacks: `just stop kepler`
4. Apply update via TrueNAS UI
5. Redeploy: `just deploy kepler`

---

## Troubleshooting

### Service on Kepler can't reach Postgres
- Check Postgres is running: `just exec kepler postgres "pg_isready -U homelab"`
- Ensure services use container name `postgres` (not Tailscale hostname) for local DB

### SWAG can't reach a service on Kepler
- Verify Tailscale mesh: `just ping-all`
- Check port is exposed: `just exec discovery swag "curl -sf http://kepler:8096"` (example for Jellyfin)
- Check nginx proxy config uses the correct Tailscale hostname and `KEPLER_HOST` is set in Discovery `.env`

### LiteLLM shows chat model as unhealthy
- Orion might be off (gaming mode). This is expected at night.
- Check: `just exec kepler litellm "curl -sf http://orion:8503/health"`
- Embed/rerank on Kepler should still be healthy

### VPN/Gluetun won't connect
- Check Gluetun logs: `just service-logs kepler media gluetun`
- Verify NordVPN service credentials (not account password) in `.env`
- Try a different country: `VPN_COUNTRIES=Netherlands`

### Wazuh indexer won't start
- Needs `vm.max_map_count=262144`. On TrueNAS: `sysctl -w vm.max_map_count=262144`
- Make it permanent: add to `/etc/sysctl.conf`

### GitLab is slow to start
- Normal — GitLab takes 3-5 minutes to boot
- Watch progress: `just logs kepler cicd`
- Needs at least 4GB RAM allocated to the container
