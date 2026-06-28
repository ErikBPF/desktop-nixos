# Local, persistent diagnostics for discovery's intermittent network loss.
#
# The push-based observability stack (Alloy → discovery's own Loki/Prometheus)
# is blind to this failure mode by construction: when discovery loses network it
# can't push, and the data would land on the very box that's flaking. So this is
# all LOCAL and survives a network drop + reboot. Motivated by the 2026-06-25
# outage whose window was lost because the fleet journal is capped at 50M.
#
# Host-only module (dendritic contract: `<host>-<capability>`). Promote to a
# reusable `host-diagnostics` if another host needs the same.
_: {
  flake.modules.nixos.discovery-diagnostics = {
    pkgs,
    lib,
    ...
  }: {
    # 1. Persistent, larger journal. Fleet default (modules/services/logrotate.nix)
    #    caps at 50M, which lost the last outage window. Override for this host:
    #    keep ~1 month on disk so a hiccup is still there days later.
    services.journald.extraConfig = lib.mkForce ''
      Storage=persistent
      SystemMaxUse=2G
      SystemKeepFree=1G
      MaxRetentionSec=1month
      MaxFileSec=1day
    '';

    # 2. Tighten sysstat (already enabled fleet-wide in modules/security/audit.nix)
    #    from the default 10-min cadence to 2-min, so `sar` per-interface error
    #    counters + load/mem/CPU around a hiccup have usable resolution.
    #    Read post-mortem with `sar -n EDEV -f /var/log/sa/saNN` (net errors),
    #    `sar -q` (load), `sar -r` (mem).
    services.sysstat.collect-frequency = "*:00/02";

    # 3. Network watchdog — every 30s snapshot link state, NIC error counters,
    #    default route and reachability into the (now persistent) journal under
    #    `net-watch`. When the network drops, the gap + the last lines pinpoint
    #    timing, and the counters/ethtool stats show whether it's the physical
    #    NIC (eno1), the bridge (br0), DHCP, or upstream.
    #    Inspect: `journalctl -t net-watch --since -2h`.
    systemd.services.net-watch = {
      description = "Local network-health snapshot (discovery instability probe)";
      path = [pkgs.iproute2 pkgs.iputils pkgs.ethtool pkgs.gawk pkgs.coreutils];
      serviceConfig = {
        Type = "oneshot";
        SyslogIdentifier = "net-watch";
      };
      script = ''
        gw=$(ip route show default | awk '/default/{print $3; exit}')
        echo "addr eno1=[$(ip -br addr show eno1 2>/dev/null)] br0=[$(ip -br addr show br0 2>/dev/null)]"
        echo "default-route: $(ip route show default 2>/dev/null | tr '\n' ';')"
        echo "eno1-counters: $(ip -s link show eno1 2>/dev/null | tr '\n' ' ' | tr -s ' ')"
        echo "eno1-ethtool: $(ethtool -S eno1 2>/dev/null | grep -iE 'err|drop|reset|carrier|timeout|fifo' | tr '\n' ' ' | tr -s ' ')"
        echo "br0-counters: $(ip -s link show br0 2>/dev/null | tr '\n' ' ' | tr -s ' ')"
        if [ -n "$gw" ]; then
          ping -c1 -W2 "$gw" >/dev/null 2>&1 && echo "gw $gw OK" || echo "gw $gw UNREACHABLE"
        else
          echo "gw NONE (no default route)"
        fi
        ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && echo "wan 1.1.1.1 OK" || echo "wan 1.1.1.1 FAIL"
      '';
    };
    systemd.timers.net-watch = {
      description = "Run net-watch every 30s";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "30s";
        AccuracySec = "1s";
      };
    };
  };
}
