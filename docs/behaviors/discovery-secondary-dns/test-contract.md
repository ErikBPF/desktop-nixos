# Discovery secondary DNS test contract

**Status:** Draft P3 contract; offline tests precede any deployment or apply

## Test boundary

Offline fixtures and Nix evaluation do not contact Kepler, vanguard, Discovery,
UniFi, or Tailscale. Desktop deployment, wired IaC apply, DHCP renewal, and the
AdGuard outage drill are separate live gates. No test helper may stop a service,
apply Terraform/OpenTofu, edit a remote file, or change a DHCP lease.

## Desktop fixture matrix

| Fixture | Expected result |
|---|---|
| Vanguard default tailnet role | Bind/firewall only `tailscale0`; accept |
| Vanguard public or wildcard listener | Halt |
| Kepler exact LAN listener | TCP/UDP 53 only on Kepler LAN; accept |
| Kepler wildcard, public, or tailscale listener | Halt |
| Missing or unknown listener interface/address | Halt evaluation |
| Existing conflicting port 53 listener | Halt live preflight |
| Every declared fleet ingress zone has a local A synthesis | Accept |
| Missing ingress host/IP or zone | Halt evaluation |
| Fleet zone forwarded to Discovery or public DNS | Halt |
| Kepler external forwarding: AdGuard first, approved fallback second | Accept |
| Public-first or empty Kepler upstream list | Halt |
| Global firewall TCP/UDP 53 | Halt |
| Vanguard configuration changes while adding Kepler | Halt regression gate |

## Static assertions

- `services.fleetDns` remains the single implementation; do not create a second
  per-host DNS module.
- Listener and firewall defaults preserve vanguard's tailnet-only behavior.
- Kepler's role binds the exact LAN surface and has no wildcard listener.
- TCP and UDP 53 are opened only on the matching interface.
- CoreDNS locally synthesizes all `fleet.ingress` zones from desktop-owned
  fleet facts.
- Fleet zones never depend on AdGuard or a public resolver.
- Kepler external forwarding is sequential: AdGuard primary, then exact
  approved independent upstreams during failure.
- Public resolver addresses do not appear in the DHCP consumer artifact.
- Generated configuration is deterministic under attribute-order changes.
- No generated command edits a remote host or mutates UniFi.

## Desktop verification gate

Before deployment:

- module unit/eval fixtures pass;
- `just lint` and `just fmt-check` pass;
- `just dry kepler` and `just dry vanguard` pass;
- a full flake check passes on an approved remote builder;
- the vanguard Corefile, listener, firewall, and service ordering remain
  semantically unchanged;
- the Kepler closure diff contains only the intended CoreDNS role/firewall
  support.

Read-only live preflight must prove Kepler TCP/UDP 53 are free, its LAN address
is present, and vanguard still answers fleet and external queries over the
tailnet. Drift blocks deployment.

After deploying Kepler through the documented `just` channel, direct
`192.168.10.230` probes must cover UDP and TCP fleet A, fleet AAAA/NODATA,
external A and AAAA, NXDOMAIN, service activity, restart count, listener
addresses, firewall exposure, and clean relevant logs. Reboot Kepler and repeat
before changing DHCP.

## Homelab-IaC contract

The planned Main-network DHCP list is exactly:

```text
192.168.10.210
192.168.10.230
```

Tests must reject reversed order, missing primary, public resolvers, tailnet
addresses, unknown LAN addresses, duplicates, and more than two entries.

Repository gates require formatting, validation, provider-lock consistency,
security checks, refreshed state, and a saved plan with checksum. The plan must
show exactly one intended Main-network DHCP DNS change and no Default-network,
VLAN, WLAN, subnet, pool, reservation, static-DNS, Tailscale, Cloudflare, or
remote-state mutation. Unrelated drift halts. Apply is wired-only.

## Generic-client and outage fixtures

Offline state-machine fixtures cover:

1. Lease lacks secondary: no outage action.
2. Client has Tailscale/NetBird: not valid generic-client evidence.
3. Missing/ambiguous RA evidence, more than one RDNSS server, resolver-order
   drift, or an observed RDNSS path that differs from the approved
   fleet/external/NXDOMAIN/filtering contract over UDP or TCP: halt. An exact
   gateway RDNSS path may proceed only when it is bound into the observation,
   placed first in the namespace resolver order, and re-proved before and after
   the outage with nonce-derived queries. While AdGuard is stopped, gateway
   RDNSS is a bounded diagnostic and may be unavailable without failing P3.
4. Secondary direct UDP works but TCP fails: halt.
5. Fleet works but external fails, or external works but fleet fails: halt.
6. Explicit secondary works but system resolver never fails over within the
   observation-bound ceiling: halt. The approved live harness accepts only a
   positive ceiling of at most 10,000 ms and records the actual elapsed time.
7. Recovery path requires DNS: halt before stopping AdGuard.
8. AdGuard/exporter exact stop, successful failover, exact restore, and both
   resolvers healthy: pass.
9. Attempt to stop SWAG or another networking service: halt.
10. Repeated successful evidence produces the same value-free result shape.
11. Any implementation, pinned-host-key, approved container identity, image,
    mount, network, restart-policy, or unrelated project-container drift before
    the stop: halt.
12. Recovery makes at most three bounded attempts, retains a value-free journal
    on every outcome, and always targets the same approved container IDs.
13. The four required outage workers — system UDP/TCP and Kepler UDP/TCP — use
    one fresh shared nonce and produce exactly 24 canonical rows. Any missing
    fleet, external, NXDOMAIN, filtering, UDP, or TCP result halts and restores
    AdGuard. The system fleet A must be the private `.210` answer and filtering
    must be NXDOMAIN/zero or `0.0.0.0`, preventing public fallback from masking
    a failed Kepler path.
14. Gateway RDNSS UDP/TCP workers run concurrently under the same bound but are
    diagnostic-only during the outage. Their 0–12 canonical rows, terminal
    statuses, and partial/full hashes are separate from the required 24-row
    success hash. Their failure must not delay recovery or contaminate required
    or post-restore evidence.
15. Gateway RDNSS succeeds only from cache, changes router/prefix/lifetime, or
    fails its full post-restore contract: halt. A bounded during-outage RDNSS
    timeout or malformed response alone does not fail the amended v4 gate.

Live evidence records only resolver addresses, query names selected for the
contract, record types, response codes/counts, latency bounds, service states,
and timestamps. It must not record client query history, credentials,
environment, full packet captures, or unrelated DNS traffic.

The fleet ingress zone is intentionally wildcard-synthesized: an arbitrary A
name under the zone must return its fronting host IP, while AAAA is
NOERROR/NODATA. NXDOMAIN is tested with a reserved nonexistent external name;
an unknown fleet-zone A name is not an NXDOMAIN case.

## Rollback tests

- Saved rollback restores the previous DHCP resolver list before host-role
  disablement.
- A renewed generic client proves the restored list.
- Disabling Kepler CoreDNS while DHCP still advertises it is forbidden.
- Rollback does not alter vanguard, AdGuard data, SWAG, P2 evidence, or any
  retained volume/snapshot/archive.
- Stored command text is never evaluated.

## Success gate

P3 passes only when fresh evidence proves the Kepler LAN resolver, preserved
vanguard tailnet resolver, narrow DHCP apply, generic-client lease, actual
system-resolver failover and direct Kepler UDP/TCP during the approved AdGuard
outage, successful exact-ID restore, and full post-restore gateway/AdGuard/
Kepler health. During-outage gateway RDNSS evidence is diagnostic-only. The
final artifact states that P2 mutation remains a separate manifest-bound
approval.
