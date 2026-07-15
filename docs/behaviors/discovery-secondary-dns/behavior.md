# Discovery secondary DNS

**Status:** Amended P3 behavior; a new v4 manifest and exact approval are required

## Outcome

Generic LAN clients retain fleet and external DNS resolution while Discovery
AdGuard is stopped. Kepler provides the LAN-reachable secondary resolver at
`192.168.10.230:53`. Vanguard remains the independent tailnet resolver at its
Tailscale address and is not exposed publicly or routed directly to generic LAN
clients.

## Phase-order amendment

The safe execution order is:

1. Complete P2 fixtures and read-only preflight.
2. Implement P3 and prove the secondary during an approved AdGuard outage.
3. Return to the separately approved P2 mutation.

This resolves the proposal's ordering tension: its phase list places P3 after
P2 adoption, while its P3 safety requirement says the secondary must work
before AdGuard maintenance. The amendment advances only the P3 safety
interlock. It does not authorize P2 container recreation, P4 Terraform
ownership, or P5 storage migration.

## Ownership and scope

- `desktop-nixos` owns the CoreDNS module, Kepler service, firewall, fleet
  ingress/address facts, deployment, and host verification.
- `homelab-iac` owns the UniFi Main-network DHCP resolver list and its saved
  plan, apply, and rollback.
- Vanguard's existing tailnet-only CoreDNS remains active and unchanged.
- Servarr, AdGuard API configuration, SWAG, Cloudflare, and public DNS are not
  changed by P3.

P3 does not add a LAN route into `100.64.0.0/10`. Generic LAN clients cannot
directly reach vanguard's Tailscale address, and a static route would add a
subnet-router, SNAT, ACL, and gateway dependency. Public resolvers are never
advertised by DHCP because they cannot resolve fleet zones.

## Required host behavior

1. Reuse the existing `services.fleetDns` implementation. Parameterize only the
   listener/firewall and upstream behavior needed for its two roles.
2. Preserve vanguard's current contract:
   - bind only `tailscale0`;
   - allow TCP and UDP 53 only on `tailscale0`;
   - synthesize fleet ingress zones locally;
   - remain reachable to allowed tailnet peers;
   - never listen on its public interface.
3. Enable the LAN role on Kepler:
   - bind only Kepler's LAN interface or exact `192.168.10.230` address;
   - allow TCP and UDP 53 only on that LAN surface;
   - never bind wildcard, public, or tailnet listeners for this role;
   - synthesize every `fleet.ingress` zone locally from the desktop fleet SSOT;
   - forward external names sequentially to AdGuard first, then to approved
     independent upstreams only while AdGuard is unhealthy.
4. A normally selected secondary must not bypass AdGuard filtering. Public
   upstreams are degraded fallback inside CoreDNS, not normal DHCP resolvers.
5. CoreDNS startup must wait for its bound interface/address and restart safely
   on a boot race. It must not collide with `systemd-resolved` or another port
   53 listener.

## DHCP boundary

Only after Kepler answers direct LAN probes and survives reboot may
`homelab-iac` propose this exact Main-network DHCP resolver order:

1. `192.168.10.210` — Discovery AdGuard primary.
2. `192.168.10.230` — Kepler CoreDNS secondary.

The saved plan must change only the Main network's DHCP DNS list. Default LAN,
VLAN, WLAN, subnet, pool, reservations, static DNS, Tailscale, and Cloudflare
resources remain unchanged. Apply occurs only from a wired LAN host after plan
and checksum inspection. Existing clients must renew their leases before their
resolver list is evidence.

## Outage proof

An outage drill is a separately approved live mutation because it stops
AdGuard. Before the stop, recovery commands and artifacts must be available by
IP without DNS.

The drill must:

1. Use a generic LAN client with no Tailscale or NetBird dependency.
2. Confirm its renewed lease contains exactly the primary and secondary in the
   declared order.
3. Confirm both resolvers answer before the outage.
4. Stop only AdGuard and its dependent exporter through the fixed approved
   workflow; keep SWAG and unrelated networking services running.
5. Prove the client's normal resolver path fails over within a recorded bound.
6. Prove direct secondary UDP and TCP queries answer fleet A, the declared
   fleet AAAA/NODATA contract, external A and AAAA, and NXDOMAIN behavior.
7. Observe the gateway RDNSS UDP and TCP paths concurrently and retain their
   bounded complete or partial diagnostic evidence. A brief gateway/local DNS
   provider outage is accepted here because router redundancy preserves
   Internet access; this diagnostic does not gate the outage result.
8. Restore AdGuard and verify the gateway RDNSS, both declared resolvers,
   normal primary filtering, SWAG,
   and dependent DNS paths.

Direct `dig` success alone is insufficient: the generic client's actual system
resolver must fail over. During the outage, success requires the complete
system-resolver and direct-Kepler matrices over UDP and TCP within one
10-second bound. They use the same fresh nonce, and the system path must return
the private fleet answer plus the filtering-policy response so public fallback
cannot mask a failed Kepler path. IPv6 RA/RDNSS must be inspected so it cannot
silently replace the intended DHCP contract; it remains mandatory before and
after the outage but is diagnostic-only while AdGuard is stopped.

## Failure and rollback

Any port collision, listener exposure, unrelated IaC drift, failed plan
checksum, missing wired path, incomplete DHCP lease, excessive failover, fleet
resolution failure, or external resolution failure stops P3.

DHCP rollback happens first: restore the previous Main-network resolver list
through an inspected wired plan, renew and probe a client, then disable the
Kepler role if necessary. Never leave DHCP advertising a dead resolver.
Vanguard remains unchanged throughout rollback.

## Completion

P3 completes only after:

- Kepler and vanguard pass their distinct listener/firewall contracts;
- Kepler passes direct probes before and after reboot;
- the narrow wired UniFi apply succeeds with no unrelated drift;
- a renewed generic LAN client receives the exact resolver list;
- the approved AdGuard outage drill proves fleet and external failover;
- restoration proves both resolvers and primary filtering are healthy.

Completion authorizes returning to the P2 approval gate. It authorizes no P2
mutation by itself.
