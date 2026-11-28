# goflow2 IPFIX collector

**Status:** Implemented on `kepler`; gateway export is not enabled by this change.

`kepler` runs `goflow2` as a local IPFIX v10 collector for the UDM LAN
gateway at `192.168.10.1`. The process writes no flow records: it reads the
gateway's IPFIX packets, exports its own Prometheus counters, and discards the
records. Alloy scrapes those counters and remote-writes them to the fleet
Prometheus.

## What this proves

- The gateway sends IPFIX v10 packets to `192.168.10.230:2055`.
- The packets arrive through the source-restricted firewall chain
  (`kepler-ipfix` accepts only `192.168.10.1/32`).
- `goflow2` parses the packets: the template and data-set counters advance, and
  the decoder-error counter stays flat.
- The collector process is healthy: Alloy scrapes `/metrics` and the
  Prometheus series are present.

## What this cannot prove

- **Completeness.** IPFIX uses UDP. A missing packet is invisible unless the
  gateway exposes its own export counters. `goflow2_flow_dropped_*` counts only
  drops inside the collector, not drops on the wire.
- **Gateway accounting.** Sampling, aggregation, and active-timeout policy are
  set on the gateway. The collector observes samples; it does not observe every
  forwarded byte.
- **Traffic byte totals.** With flow records discarded, the Prometheus counters
  measure IPFIX envelope bytes and packets, not the sampled flow bytes inside
  them. Do not compare `goflow2_flow_traffic_bytes_total` with a gateway
  traffic counter; the quantities differ.
- **Direction or interface correctness.** Interface IDs need a mapping file or
  a gateway export that uses the standard fields. This deployment has no
  mapping file.

To test sampling or aggregation, export the flow records (file transport or
`nfdump`) and compare their byte totals with the gateway's own interface or
client byte counters for the same interval. That comparison is a separate
change; it is not available from the default metrics path.

Raw record retention is deliberately absent. The collector is a metrics source,
not an audit store. Add `nfdump` or a file transport only when a question needs
per-flow history that Prometheus counters cannot answer.

## Configuration

NixOS module: `modules/hosts/kepler/goflow2.nix`.

The unit runs:

```
goflow2 -listen=netflow://192.168.10.230:2055?workers=2&queue_size=50000 \
        -addr=127.0.0.1:8081 -transport=file -transport.file=/dev/null \
        -loglevel=info
```

`netflow://` is goflow2's scheme for NetFlow v5/v9 and IPFIX v10. The listen
address is explicit, so the socket binds only the LAN address. The HTTP
endpoint binds loopback only and serves `/metrics` and `/__health`. The unit
runs as a dynamic user with `MemoryMax=256M`, `CPUQuota=50%`, `Restart=always`,
and journal logging.

Firewall chain, from `modules/hosts/kepler/networking.nix`:

```
iptables -N kepler-ipfix
iptables -F kepler-ipfix
iptables -A kepler-ipfix -s 192.168.10.1/32 -p udp -m udp --dport 2055 -j ACCEPT
iptables -A kepler-ipfix -j REJECT --reject-with icmp-port-unreachable
iptables -D INPUT -p udp -m udp --dport 2055 -j kepler-ipfix
iptables -A INPUT -p udp -m udp --dport 2055 -j kepler-ipfix
```

`2055` is not in `allowedUDPPorts`. Adding it there would accept every source
and make the chain irrelevant.

Alloy job, from `modules/hosts/kepler/monitoring.nix`:

```alloy
prometheus.scrape "goflow2" {
  targets = [{
    "__address__" = "127.0.0.1:8081",
    "job"         = "goflow2",
    "host"        = "kepler",
  }]
  metrics_path    = "/metrics"
  forward_to      = [prometheus.remote_write.prometheus.receiver]
  scrape_interval = "30s"
}
```

## Metrics

Dashboards bind to the `goflow2_` namespace:

| Metric | Type | Use |
|--------|------|-----|
| `goflow2_flow_traffic_bytes_total` | counter | Bytes received by the collector, by remote IP and protocol type. |
| `goflow2_flow_traffic_packets_total` | counter | IPFIX packets received. |
| `goflow2_flow_traffic_size_bytes` | summary | IPFIX packet size. |
| `goflow2_flow_dropped_bytes_total` | counter | Bytes dropped before processing. |
| `goflow2_flow_dropped_packets_total` | counter | Packets dropped before processing. |
| `goflow2_flow_process_nf_total` | counter | NetFlow/IPFIX messages processed, by router and version. |
| `goflow2_flow_process_nf_errors_total` | counter | NetFlow/IPFIX processing errors. |
| `goflow2_flow_process_nf_flowset_total` | counter | FlowSets processed, by type (`data-template`, `data`, `options`). |
| `goflow2_flow_process_nf_flowset_records_total` | counter | Records inside processed FlowSets. |
| `goflow2_flow_process_nf_templates_total` | counter | Data and option templates observed. |
| `goflow2_flow_process_nf_delay_seconds` | summary | Time between flow start and processing. |
| `goflow2_flow_decoder_error_total` | counter | Decode failures, by router and error name. |
| `goflow2_flow_decoding_time_seconds` | summary | Decode duration. |

For IPFIX v10, `version="10"` and `type="netflow"`. The `goflow2_` series do
not exist until the first IPFIX packet arrives; before that, `/metrics` serves
only Go and process metrics. A healthy first check is
`goflow2_flow_process_nf_total{version="10"}` increasing and
`goflow2_flow_decoder_error_total` flat. Template and FlowSet counters appear
after the gateway sends its first template and data sets.

## On-host verification

Run on `kepler` after the collector is deployed and the gateway export is
enabled:

```bash
# Unit is active and listening on the LAN address and loopback metrics port.
systemctl status goflow2 --no-pager
ss -lunp | grep ':2055'
ss -ltnp | grep ':8081'

# Firewall chain and INPUT jump are present.
sudo iptables -S kepler-ipfix
sudo iptables -S INPUT | grep kepler-ipfix

# Collector metrics move after the gateway starts exporting.
curl -fsS http://127.0.0.1:8081/metrics | grep '^goflow2_'
curl -fsS http://127.0.0.1:8081/__health

# Collector logs are in the journal, and Alloy scrapes without errors.
journalctl -u goflow2 -n 50 --no-pager
journalctl -u alloy -n 50 --no-pager | grep -i goflow2

# Prometheus received the series (from a host with access to Prometheus).
curl -fsS 'https://prometheus.homelab.pastelariadev.com/api/v1/query?query=goflow2_flow_process_nf_total'
```

A source that is not the gateway must be rejected. Run this on another LAN
host, then check that the `REJECT` packet counter moves and the `ACCEPT`
counter does not:

```bash
# On another LAN host.
nc -u -w1 192.168.10.230 2055 </dev/null || true

# On kepler.
sudo iptables -L kepler-ipfix -v -n
```

Reverting the gateway export and stopping the unit leaves the host unchanged:
`sudo systemctl stop goflow2`. The firewall chain remains declaratively managed
and accepts only the gateway source.
