# Kepler goflow2 IPFIX collector

**Stage / revision:** implementation / 1
**Status:** Source implemented; targeted build and contract tests pass; not deployed. Gateway export remains disabled.
**Owner / date:** desktop-nixos / 2026-11-28

**Basis:** fleet addressing in `fleet.json`, the [collector reference](../../reference/goflow2-ipfix-collector.md), and [contract tests](../../../tests/kepler-goflow2/test_goflow2.py).

## Human seed (preserved)

> IPFIX will arrive from 192.168.10.1 (the UDM LAN address) as IPFIX v10 on UDP
> 2055. goflow2 is in nixpkgs (2.2.6). It exposes Prometheus metrics; configure it
> for IPFIX + Prometheus output. ... Do not enable NetFlow or change anything on
> the gateway; the coordinator flips that after the collector is verified.

Accepted correction from the grounded facts: the nixpkgs pin resolves goflow2
**2.2.7**, and goflow2 has no `ipfix://` scheme. `netflow://` is its scheme for
NetFlow v5/v9 and IPFIX v10. `2055` must not enter `allowedUDPPorts`; the fleet
firewall backend is iptables.

## Outcome

Kepler can now receive IPFIX v10 from the UDM gateway at `192.168.10.1`, expose
goflow2's Prometheus counters on loopback, and remote-write them through the
existing host Alloy pipeline. The collector drops flow records, so the change
adds no raw-retention store and no `nfdump` dependency.

## Changes

- [`modules/hosts/kepler/goflow2.nix`](../../../modules/hosts/kepler/goflow2.nix)
  runs `goflow2` with an explicit `192.168.10.230:2055` listener, loopback
  `127.0.0.1:8081` metrics endpoint, bounded queue, `MemoryMax=256M`,
  `CPUQuota=50%`, `Restart=always`, dynamic user, and journal logging. Records
  go to `/dev/null`.
- [`modules/hosts/kepler/networking.nix`](../../../modules/hosts/kepler/networking.nix)
  adds the `kepler-ipfix` chain: accept UDP 2055 only from `192.168.10.1/32`,
  reject the rest, delete the previous INPUT jump, then append the new jump.
- [`modules/hosts/kepler/monitoring.nix`](../../../modules/hosts/kepler/monitoring.nix)
  adds `prometheus.scrape "goflow2"` at `127.0.0.1:8081` with job name
  `goflow2`, forwarding to `prometheus.remote_write.prometheus.receiver`.
- Kepler's host module imports the new leaf, CI runs the new contract suite,
  and the reference records metric names, limits, and on-host checks.

## Evidence

- `python3 -m pytest -q tests/kepler-goflow2` → **5 passed**.
- `nix build .#nixosConfigurations.kepler.config.system.build.toplevel` →
  **exit 0** (built locally and on the Orion builder).
- Rendered unit contains the exact listener, metrics address, resource caps,
  and restart policy; `nix eval` also shows `2055` absent from
  `allowedUDPPorts` (`[111 4000 4001 5514 21027 41641]`).
- Rendered firewall commands contain the source-restricted chain and both
  idempotency steps.
- Alloy `validate` accepts the concatenated Kepler configuration (exit 0).
- A disposable local goflow2 instance with a synthetic IPFIX v10 header emitted
  `goflow2_flow_process_nf_total{version="10"}` and
  `goflow2_flow_traffic_{bytes,packets}_total`, confirming the metric names.
- `alejandra --check`, `statix check`, and `just docs-check` pass.

Limits: the real gateway export is off, so no real IPFIX traffic, template
learning, or accounting comparison was observed. Builds do not prove service
startup.

## Decisions

- **Metrics only.** No record sink is configured. Prometheus counters prove
  receipt and parse health. They cannot prove flow completeness or gateway
  accounting; those comparisons need exported records plus the gateway's own
  counters.
- **Explicit listener.** Binding the LAN IP, not `:2055`, limits exposure even
  before the firewall rule runs.
- **No `allowedUDPPorts` entry.** That would accept every source and make the
  source restriction meaningless.

## Remaining work

The coordinator enables gateway IPFIX export to `192.168.10.230:2055` after
this collector is deployed. Then run the on-host checks in the reference,
confirm `version="10"` traffic, and compare the observed export volume with the
gateway counters before treating the path as complete.

## Risks and recovery

If the listener or firewall is wrong, only collector metrics are lost; the
gateway export can be disabled independently. Stop `goflow2` to halt
collection. The firewall chain stays declarative and source-restricted.
