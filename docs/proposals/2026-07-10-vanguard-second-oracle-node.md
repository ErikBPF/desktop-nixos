# vanguard — second Oracle free VM, multi-role offsite resilience node

**Status:** Built in-tree; VM provisioned 2026-07-11 but **off-network after infect (redo needed)** — 2026-07-11

> **Build note.** Host + all four role modules are in-tree and eval-clean,
> **opt-in/disabled by default** (dry-build pulls no coredns/postgres/openbao/netbird
> pkgs). R4 (vault-witness) is a gated stub that does not touch discovery's live vault.
>
> **Provision note (2026-07-11).** The shared-VCN refactor was applied and the VM
> provisioned (147.15.14.207, subnet 10.0.2.0/24). But `just infect-vanguard` ran
> with auto-reboot, and the NixOS first boot came up **off-network** (no
> DHCP/console pre-check) — SSH times out on 22 + 2222. **Redo:** `terragrunt
> destroy` the instance + `just infect-vanguard noreboot=1`, verify DHCP /
> `console=ttyS0` on the still-Ubuntu box, *then* reboot + `switch-vanguard`. No data
> lost (fresh host). **R2 webhook secret (`dead-mans-switch/discord_webhook`) is
> minted**; R1/R2 deploy once the VM is back; R3/R4 follow the phases below.

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

1. **Light pair first:** R1 (CoreDNS) + R2 (prober) — tens of MB, immediate SPOF wins.
2. **R3:** relay#2 + PG replica — watch RAM/egress; cgroup-cap the replica.
3. **R4 (optional, last):** Raft witness — only after a latency test proves quorum
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
- `homelab-iac`: `oracle/compute-vanguard` unit (mirror `compute-telstar`, E2.1.Micro,
  own VCN); `cloudflare/dns` `relay2` already staged; `tailscale/dns` add vanguard to
  the nameserver list; `tailscale/acl` allow vanguard as break-glass + DNS.

## Human-gated ops (not autonomous)

Provision the VM (`terragrunt apply` from a wired-LAN host — capacity for the 2nd AMD
micro is reliable, unlike A1) → set `fleet.hosts.vanguard.ip` → `just fleet-json` →
`just deploy vanguard <ip> 2222` (nixos-infect/disko path per voyager) → enable roles
in phases, verifying each. NetBird `NB_AUTH_SECRET` re-encrypted to vanguard's
host-specific age key (Q4). The Raft witness (R4) additionally needs the discovery
vault reconfig + a latency test before enable.

---

*Cross-refs:* [`2026-07-10-netbird-selfhosted-overlay.md`](2026-07-10-netbird-selfhosted-overlay.md)
§4a (Track-1 origin), [`implemented/2026-06-30-offsite-dr-crown-jewels.md`](../implemented/2026-06-30-offsite-dr-crown-jewels.md)
(why same-region ≠ independent), [`2026-07-01-telstar-oracle-arm-host.md`](2026-07-01-telstar-oracle-arm-host.md)
(sibling Oracle host pattern).
