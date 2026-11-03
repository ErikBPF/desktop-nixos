# Read recent systemd status and journal for the failed-unit alert allowlist.
grafana-alert-diagnostics:
    #!/usr/bin/env bash
    set -euo pipefail
    diagnose() {
      local host=$1 unit=$2
      echo ":: $host — $unit"
      if [ "$(hostname)" = "$host" ]; then
        systemctl status "$unit" --no-pager -l || true
        journalctl -u "$unit" -n 80 --no-pager || true
      else
        local ip
        ip="$(jq -r --arg host "$host" '.hosts[$host].tailscaleIp // empty' fleet.json)"
        [ -n "$ip" ] || ip="$(just _host-ip "$host")"
        ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 \
          -o ServerAliveInterval=3 -o ServerAliveCountMax=1 "erik@$ip" \
          "systemctl status '$unit' --no-pager -l || true; journalctl -u '$unit' -n 80 --no-pager || true" \
          || true
      fi
    }
    diagnose endeavour nixos-upgrade.service
    diagnose kepler nixos-upgrade.service
    diagnose orion nix-cache-builder.service
    diagnose orion nixos-upgrade.service
    diagnose discovery telstar-capture.service
    diagnose discovery homelab-iac-drift.service

# Identify the process killed by the kernel OOM detector on Discovery.
grafana-alert-oom-diagnostics:
    ip="$(jq -r '.hosts.discovery.tailscaleIp // empty' fleet.json)"; \
    [ -n "$ip" ] || ip="$(just _host-ip discovery)"; \
    ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" \
      "journalctl -k --since '-20 minutes' --no-pager | grep -Ei 'oom|out of memory|killed process' || true"

# Clear or retry only the units covered by grafana-alert-diagnostics.
grafana-alert-retry target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      endeavour-upgrade) host=endeavour; unit=nixos-upgrade.service; action=reset ;;
      kepler-upgrade) host=kepler; unit=nixos-upgrade.service; action=reset ;;
      orion) host=orion; unit=nixos-upgrade.service; action=reset ;;
      discovery-telstar) host=discovery; unit=telstar-capture.service; action=start-no-block ;;
      discovery-drift) host=discovery; unit=homelab-iac-drift.service; action=start ;;
      *) echo "target must be endeavour-upgrade, kepler-upgrade, orion, discovery-telstar, or discovery-drift" >&2; exit 2 ;;
    esac
    command="sudo systemctl reset-failed '$unit'"
    [ "$action" = start ] && command="$command && sudo systemctl start '$unit'"
    [ "$action" = start-no-block ] && command="$command && sudo systemctl start --no-block '$unit'"
    if [ "$(hostname)" = "$host" ]; then
      bash -c "$command"
    else
      ip="$(jq -r --arg host "$host" '.hosts[$host].tailscaleIp // empty' fleet.json)"
      [ -n "$ip" ] || ip="$(just _host-ip "$host")"
      ssh -p 2222 -o BatchMode=yes -o ConnectTimeout=8 "erik@$ip" "$command"
    fi

# Prove every compose host exports container identity through its native
# collector: cAdvisor on Docker, podman-exporter on rootless Podman.
verify-container-metrics:
    #!/usr/bin/env bash
    set -euo pipefail
    response=$(curl --fail --silent --show-error --get https://prometheus.homelab.pastelariadev.com/api/v1/query \
      --data-urlencode 'query=container_last_seen or podman_container_info')
    failed=0
    for host in discovery kepler orion; do
      raw_count=$(printf '%s\n' "$response" | jq --arg host "$host" '[.data.result[]? | select(.metric.host == $host)] | length')
      named_count=$(printf '%s\n' "$response" | jq --arg host "$host" '[.data.result[]? | select(.metric.host == $host and (.metric.name // "") != "")] | length')
      printf '%s raw_containers=%s named_containers=%s\n' "$host" "$raw_count" "$named_count"
      [ "$named_count" -gt 0 ] || failed=1
    done
    exit "$failed"

# Inspect the host collector when container metrics verification fails.
diagnose-container-metrics host:
    ssh -p 2222 erik@{{host}} \
      "systemctl show alloy docker --property=Id,ActiveState,SubState,Result,ActiveEnterTimestamp --no-pager; getent ahostsv4 prometheus.homelab.pastelariadev.com; curl -fsS http://127.0.0.1:12345/metrics | grep -E 'prometheus_remote_(storage|write)' || true; journalctl -b -u alloy --no-pager -n 300 | grep -Ei 'remote_write|prometheus|cadvisor|containerd|docker|factory' || true"
