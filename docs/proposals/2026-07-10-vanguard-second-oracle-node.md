# vanguard — second Oracle free VM, multi-role offsite resilience node

**Status:** ✅ Implemented — R1–R3 live + verified on vanguard (2026-07-11); R4 (vault-witness) deferred by design — 2026-07-11

> **Deployed (2026-07-11).** vanguard is a clean fleet host: NixOS 26.11 (Zokor),
> `ssh -p 2222 erik@<ip>`, tailscale `100.90.247.79`, ens3 DHCP, sops OK, 0 failed
> units. The earlier dark-boot after infect was root-caused (nixos-infect's
> **NIXOS_LUSTRATE** is only honoured by the scripted stage-1; modern NixOS defaults
> `boot.initrd.systemd.enable=true`, which skips it) and fixed in `just infect-vanguard`
> (injects `boot.initrd.systemd.enable=false` + `console=ttyS0` + `useDHCP`). Public IP
> is **ephemeral** (changes on recreate). See `memory/netbird_overlay_vanguard.md`.
>
> **Roles live (in enablement order):** **R1** `services.fleetDns` — CoreDNS secondary
> resolver, **bound to `tailscale0`** (no clash with systemd-resolved's `:53` stub),
> answers `*.homelab.<zone>` → discovery; wired into the tailnet as an offsite fallback
> (homelab-iac `tailscale/dns` nameserver list after discovery + `tailscale/acl`
> `*→vanguard:53`). **R2** `services.deadMansSwitch` — offsite prober; the role default
> `checkUrl` (ingress apex) has no SWAG cert, so it points at PocketID
> (`id.homelab.<zone>`, public 200). **R3a** `services.netbirdRelay` — public relay#2
> `relay2.<zone>:443` (WSS/QUIC) with a real Let's-Encrypt cert; `:443` opened on the
> shared Oracle SL (`oracle/compute` `relay_public_surface=true`); DNS is a **static TF
> record** at the ephemeral IP (no on-host ddclient — no Cloudflare token in sops),
> bumped on reprovision. **R3b** `services.pgReplica` — **PG18 streaming standby** of
> discovery's shared cluster (532MB, 0 bytes behind), `:5432` published on discovery's
> tailnet IP (servarr infra) + ACL-gated to vanguard; seeded once via `pg_basebackup`.
> **R4** `services.vaultWitness` — still a gated stub, deferred (needs discovery vault
> reconfig + a WAN-latency test).

Stand up the **second** Oracle Always-Free VM — **`vanguard`** — as a multi-role
offsite node. It began as the NetBird "Track-1 2nd VM"
([`2026-07-10-netbird-selfhosted-overlay.md`](2026-07-10-netbird-selfhosted-overlay.md)
§4a) but a fleet-wide resiliency scan (below) found several *other* single points
of failure a second always-on offsite box closes cheaply.

## Name

**`vanguard`** — after Vanguard 1 (1958), the oldest artificial satellite still in
orbit; fits the fleet's spacecraft theme (voyager, telstar, discovery, orion,
kepler, pathfinder, archinaut) and connotes a durable always-on anchor / quorum
witness.

## The VM (hard constraints — researched)

- **Shape:** the *second* free **AMD `VM.Standard.E2.1.Micro`** — 1 OCPU / **1 GB
  RAM**, x86_64, São Paulo (`sa-saopaulo-1`). (The A1/`telstar` path stays blocked
  on Oracle capacity; vanguard is the provisionable-now sibling of `voyager`.)
- **Public IP:** Always-Free includes **only 1 *reserved* IP per tenancy**, held by
  voyager. vanguard gets an **ephemeral** IP → its public names are kept fresh by
  **`services.ddclient` (cloudflare)**.
- **Failure domain:** São Paulo is single-AD, so vanguard can only sit in a
  **different Fault Domain** than voyager — separate rack/power, **same region +
  provider**. Good enough for hardware-fault tolerance; **not** a second geographic
  failure domain (that's why it is a poor backup-independence target — §roles).
- **RAM is the budget.** 1 GB with a 4 GB swapfile (voyager's pattern). All four
  roles at once is **tight** → **enable in phases** (§enablement), lightest first,
  each with cgroup caps.

## Fleet resiliency scan — what a 2nd offsite node fixes

| # | Area | Current SPOF | vanguard role | Fit |
|---|------|--------------|---------------|-----|
| R1 | **Fleet DNS** | AdGuard on discovery is the *only* internal resolver; discovery down = no fleet name resolution (public fallback only) | **Secondary resolver** (CoreDNS/Unbound — lighter than AdGuard) added to the MagicDNS nameserver list | ✅ good |
| R2 | **Alert egress** | Grafana→Discord runs *inside* the home; a whole-home/ISP outage yields **silence, not an alert** | **External dead-man's-switch**: offsite blackbox prober watching the fleet + independent Discord egress | ✅ good (offsite is the point) |
| R3 | **NetBird relay** | single public relay (voyager) | **relay#2** (`relay2.<zone>`, already in `fleet.json`) + **Postgres read-replica** for faster NetBird DR (RTO ≪ 168 h TTL) | ◐ relay tiny; replica is the RAM cost |
| R4 | **OpenBao/Vault** | single Raft node (discovery) — the runtime-secret SSOT | **Raft witness / 3rd voter** (already Raft integrated-storage → no backend migration) | ◐ WAN-fsync latency; **higher risk** |
| R5 | **Break-glass** | voyager is the *sole* offsite public-SSH jump | redundant hardened jump (rides the relay box) | ◐ free with R3 |

**Rejected (recon-backed):**
- **k3s etcd witness** — the 3 CP members are microVMs on the *single* kepler host,
  so a remote witness is cosmetic against the real SPOF (the host); embedded etcd is
  WAN-fragile and a 1 GB box can't host a real CP. ❌
- **2nd backup target for 3-2-1 independence** — same region/AD/provider as voyager
  is *not* an independent failure domain; the offsite-DR doc's genuine 3rd copy is
  **GitHub** (different provider). vanguard could add offsite *capacity*, not
  diversity. ❌

## Roles in detail

**R1 — Secondary fleet DNS.** Run **CoreDNS** (or Unbound) on vanguard, forwarding
public queries and serving/forwarding fleet names; add vanguard's tailnet IP to the
`homelab-iac tailscale/dns` MagicDNS nameserver list *after* discovery's. Fleet name
resolution then survives discovery-down. Bonus: directly retires the NetBird §4b
bootstrap chicken-egg (a resolver that isn't discovery). Low RAM (~30 MB CoreDNS).

**R2 — External dead-man's-switch.** A `blackbox_exporter` + a small prober unit on
vanguard checks the home fleet's reachability (SWAG ingress, tailnet, a heartbeat
endpoint) from *outside*; if the fleet goes silent past a threshold, vanguard POSTs
to an **independent Discord webhook** (its own, not the in-home one). This is the
current blind spot — nothing today alerts when the *whole home* is dark. Tiny RAM.

**R3 — NetBird relay#2 + Postgres read-replica.** Reuse the existing
`modules/hosts/voyager/netbird-relay.nix` (`enableDdclient = true` for the ephemeral
IP); advertise `relay2.<zone>`. Add a **Postgres streaming read-replica** of
discovery's NetBird DB so DR promotion is minutes, not a snapshot-restore (NetBird
RFC §7). Replica is the main RAM consumer — tune `shared_buffers` small.

**R4 — OpenBao Raft witness (higher-risk, opt-in, phase last).** Vault is already
**Raft integrated-storage** (no backend migration needed). vanguard could join as a
**3rd voter** for Vault HA. **Caveats, loud:** (a) every quorum *write* would take a
cross-region round-trip (São Paulo ↔ home) — Raft is fsync/latency-sensitive; (b)
with discovery the only on-prem voter, 2 of 3 voters end up offsite, so a home-uplink
outage leaves quorum alive but unable to serve on-prem consumers; (c) requires moving
discovery's `cluster_addr` off loopback + `retry_join` + a TLS decision. **Recommend
deferring** until R1–R3 are proven; build it as a separate gated module that does
**not** touch discovery's live vault until explicitly enabled.

**R5 — Redundant break-glass.** vanguard's hardened public 2222 (key-only, non-root,
fail2ban) is a 2nd offsite entry beside voyager — free alongside R3's public surface.

## Enablement phases (RAM-aware)

1. ✅ **Light pair (shipped 2026-07-11):** R1 (CoreDNS) + R2 (prober) — tens of MB, immediate SPOF wins.
2. ✅ **R3 (shipped 2026-07-11):** relay#2 + PG18 read-replica. The replica is the RAM cost
   (`shared_buffers=64MB`); physical replication is whole-cluster, but discovery's is only 532MB,
   well within vanguard's disk. **No replication slot** — deliberately, so a vanguard outage can't
   fill discovery's WAL disk; if the standby lags past WAL retention it breaks and is re-seeded
   (`pg_basebackup`, cheap at 532MB).
3. **R4 (optional, last — not started):** Raft witness — only after a latency test proves quorum
   writes stay acceptable; reversible.

## Build artifacts (this proposal → code)

- `modules/hosts/vanguard/{default,hardware,networking}.nix` — x86 micro, mirrors
  `voyager` (nixos-infect origin, ephemeral IP, ddclient, rootless podman, 1 GB
  trims: no Alloy, zram, tmpfs off).
- `modules/meta.nix` `fleet.hosts.vanguard` (role server, ip unset until provisioned,
  like telstar) + `fleet.json`; `modules/deploy-rs.nix` node.
- Role modules, **opt-in/disabled by default**: `services.fleetDns` (CoreDNS
  secondary), `services.deadMansSwitch` (offsite prober), reuse `netbird-relay`
  (`relay2`), `services.pgReplica` (NetBird DB), `services.vaultWitness` (Raft, gated,
  does not alter discovery until enabled).
- `homelab-iac` (all applied 2026-07-11): `oracle/compute-vanguard` (E2.1.Micro, **shares
  voyager's VCN** — free tier caps VCNs at 2/region — subnet 10.0.2.0/24); `oracle/compute`
  `relay_public_surface=true` opens `:443` on the shared security list for relay#2 (that apply
  also surfaced + fixed a latent shape mismatch that had voyager mis-declared as A1.Flex);
  `cloudflare/dns` `relay2` → vanguard (static A record); `tailscale/dns` adds vanguard after
  discovery in the global nameserver list; `tailscale/acl` grants `*→vanguard:53` (R1),
  `vanguard→discovery:5432` (R3b), and break-glass SSH via the existing admin `*:2222` rule.
  servarr publishes discovery's postgres `:5432` on its tailnet IP for R3b.

## Human-gated ops (not autonomous)

**Done (2026-07-11):** provisioned via `terragrunt apply` (shared-VCN) → `just infect-vanguard`
(the lustrate fix) → `just switch-vanguard`, then R1 → R2 → R3 enabled + verified per phase.
`NB_AUTH_SECRET` is shared with discovery's management via sops and decrypts on vanguard through
the primary age key — no separate host key was needed, so Q4's per-host-key plan was not required
given the primary-key staging model. R3b's one-time manual steps (the module is deliberately not
turnkey): the `replicator` role + `host replication` pg_hba lines on discovery's postgres (runtime
state in the volume — re-add on a fresh init) and the `pg_basebackup` seed + standby marker on
vanguard.

**Remaining:** R4 (vault-witness) — needs the discovery vault reconfig (`cluster_addr` off
loopback + `retry_join` + a TLS decision) and a WAN-latency test proving cross-region quorum
writes stay acceptable, before enable.

---

*Cross-refs:* [`2026-07-10-netbird-selfhosted-overlay.md`](2026-07-10-netbird-selfhosted-overlay.md)
§4a (Track-1 origin), [`implemented/2026-06-30-offsite-dr-crown-jewels.md`](../implemented/2026-06-30-offsite-dr-crown-jewels.md)
(why same-region ≠ independent), [`2026-07-01-telstar-oracle-arm-host.md`](2026-07-01-telstar-oracle-arm-host.md)
(sibling Oracle host pattern).
