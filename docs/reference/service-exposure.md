# Discovery service exposure — as-built audit

**Status:** Reference (as-built)
**Date:** 2026-07-01 (audit run live via `ss -tulpn` + `docker ps`)
**Why:** P0 item 4.2 of
[`2026-06-24-source-backed-host-improvements.md`](../proposals/2026-06-24-source-backed-host-improvements.md)
— rootful Docker publishes ports through its own iptables chain, **bypassing
the NixOS firewall**, and discovery is the public ingress/DNS/media host. This
doc records what is intentionally reachable and from where. Re-audit with
`just verify-firewall discovery` and diff against the tables below.

## NixOS firewall allowlist (applies to non-Docker sockets only)

From `modules/hosts/discovery/networking.nix`: TCP `53 80 443 22000 32400`,
UDP `53 21027`, plus `2222` (sshd `openFirewall`) and `8200` on `tailscale0`
only (OpenBao). Everything else non-Docker is dropped — e.g. `rpcbind :111`
listens on `0.0.0.0` (NFS client dependency) but is not in the allowlist, so
it is unreachable from the network.

## LAN-reachable — Docker-published (firewall bypassed)

| Port | Proto | Bound to | Container | Purpose | Intentional? |
|---|---|---|---|---|---|
| 80, 443 | tcp | 0.0.0.0 | `swag` | Reverse-proxy ingress (LE certs); the sanctioned edge for all internal UIs | ✅ (also allowlisted) |
| 53 | tcp/udp | 192.168.10.210 | `adguard` | LAN DNS | ✅ (deliberately IP-bound) |
| 3000, 8090 | tcp | 192.168.10.210 | `adguard` | AdGuard UI (3000) + alt HTTP (8090) | ✅ (IP-bound) |
| 9000–9001 | tcp | 192.168.10.210 | `minio-tfstate` | tofu-state S3 + console | ✅ (IP-bound) |
| 9090 | tcp | 0.0.0.0 | `prometheus` | Fleet `remote_write` target (hosts push over Tailscale) | ⚠️ needed for tailnet push; LAN exposure is incidental |
| 3100 | tcp | 0.0.0.0 | `loki` | Fleet log push (same pattern) | ⚠️ same as 9090 |
| 6443 | tcp | 0.0.0.0 | `k8s-apiserver` | Proxy to kepler k3s apiserver (kubectl access) | ⚠️ apiserver has its own authn; LAN-wide reach is broad |
| 8085 | tcp | 0.0.0.0 | `harbor-nginx` | Harbor registry edge (k3s mirror pulls, workstation pushes) | ✅ |
| 9080 | tcp | 0.0.0.0 | `gluetun` → qbittorrent | Torrent UI (VPN-tunnelled container) | ⚠️ LAN convenience; also behind swag |
| 9696 | tcp | 0.0.0.0 | `gluetun` → prowlarr | Indexer UI | ⚠️ LAN convenience; also behind swag |
| 5055 | tcp | 0.0.0.0 | `seerr` | Request UI | ⚠️ LAN convenience; also behind swag |
| 1900, 7359 | udp | 0.0.0.0 | `jellyfin` | DLNA / client discovery (LAN protocols) | ✅ |
| 32400 | tcp | * | `plex` (host net) | Plex — allowlisted in the NixOS firewall | ✅ |

## Loopback / tailnet only (not LAN-reachable)

| Port | Bound to | Service | Notes |
|---|---|---|---|
| 8200 | 127.0.0.1 + tailnet IP | OpenBao (`bao`) | tailnet listener allowlisted on `tailscale0` only |
| 8384 | 127.0.0.1 | syncthing GUI | |
| 8888 | 127.0.0.1 | atuin-server | |
| 12345 | 127.0.0.1 | alloy | |
| 5432 | 127.0.0.1/::1 | host postgres | container `postgres` is compose-network only |
| 1514 | 127.0.0.1 | `harbor-log` (syslog) | |
| 32401, 32600, … | 127.0.0.1 | Plex internals | |

Everything else (`litellm`, `vaultwarden`, `grafana`, `langfuse`, `homepage`,
`uptime-kuma`, *arr stack, `healthchecks`, `stirling-pdf`, …) publishes **no**
host port — reachable only through the compose network, i.e. via swag vhosts.
That is the target pattern: **reverse-proxy exposure over host port
publishing**.

## Internet ingress

- `swag` 80/443 is the only internet-facing edge (Cloudflare in front; DNS-01
  certs). `cloudflared` runs an outbound tunnel (no listener).
- Tailnet reach is gated by the default-deny tailnet ACL (`homelab-iac`).

## Follow-up candidates (decisions, not yet done — `TODO(erik)`)

1. **Bind `prometheus`/`loki` to the tailnet IP** (`100.76.140.121`) instead
   of `0.0.0.0` — fleet pushes arrive over Tailscale, so LAN exposure buys
   nothing. Verify no LAN-path pusher first (kepler/orion alloy configs).
2. **Drop LAN publishes for `seerr`/`gluetun` UIs (5055/9080/9696)** if the
   swag vhosts cover daily use.
3. **`k8s-apiserver` 6443** — consider tailnet-IP binding as well; kubectl
   users are on the tailnet.
