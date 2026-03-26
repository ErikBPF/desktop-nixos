{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.modules.security.tor-monitor;
  logDir = "/home/erik/Documents/erik/desktop-nixos/logs";

  torBlocklistScript = pkgs.writeShellScript "update-tor-blocklist" ''
    set -euo pipefail

    DIR=/var/lib/tor-monitor
    LIST="$DIR/exit-nodes.txt"
    TMP="$DIR/exit-nodes.tmp"

    # Fetch Tor bulk exit list
    ${pkgs.curl}/bin/curl -sS --max-time 30 \
      https://check.torproject.org/torbulkexitlist \
      | ${pkgs.gnugrep}/bin/grep -E '^[0-9]+\.' \
      > "$TMP" || true

    # Fetch running relay IPs from Onionoo
    ${pkgs.curl}/bin/curl -sS --max-time 60 \
      'https://onionoo.torproject.org/details?type=relay&running=true' \
      | ${pkgs.jq}/bin/jq -r '.relays[].or_addresses[]' \
      | ${pkgs.gnugrep}/bin/grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
      >> "$TMP" || true

    # Deduplicate
    sort -u -o "$LIST" "$TMP"
    rm -f "$TMP"

    COUNT=$(wc -l < "$LIST")
    echo "Loaded $COUNT unique Tor relay IPs"

    mkdir -p ${logDir}
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Blocklist updated: $COUNT Tor relay IPs" >> "${logDir}/tor-blocklist.log"

    # Rebuild ipset atomically
    ${pkgs.ipset}/bin/ipset create tor_nodes_new hash:ip hashsize 65536 maxelem 1048576 2>/dev/null || \
      ${pkgs.ipset}/bin/ipset flush tor_nodes_new
    while IFS= read -r ip; do
      ${pkgs.ipset}/bin/ipset add tor_nodes_new "$ip" 2>/dev/null || true
    done < "$LIST"

    # Swap in the new set
    ${pkgs.ipset}/bin/ipset create tor_nodes hash:ip hashsize 65536 maxelem 1048576 2>/dev/null || true
    ${pkgs.ipset}/bin/ipset swap tor_nodes_new tor_nodes
    ${pkgs.ipset}/bin/ipset destroy tor_nodes_new 2>/dev/null || true

    # Ensure iptables LOG rule exists (idempotent)
    iptables -C OUTPUT -m set --match-set tor_nodes dst -j LOG --log-prefix "[TOR-NODE] " --log-level 4 2>/dev/null \
      || iptables -I OUTPUT 1 -m set --match-set tor_nodes dst -j LOG --log-prefix "[TOR-NODE] " --log-level 4
  '';

  torAlertScript = pkgs.writeShellScript "tor-alert" ''
    mkdir -p ${logDir}
    LOGFILE="${logDir}/tor-alerts.log"

    ${pkgs.systemd}/bin/journalctl -kf --grep="TOR-" | while IFS= read -r line; do
      timestamp=$(date '+%Y-%m-%d %H:%M:%S')
      # Extract destination IP from the kernel log line
      dst=$(echo "$line" | ${pkgs.gnugrep}/bin/grep -oP 'DST=\K[0-9.]+' || true)
      proc_info=""
      if [ -n "$dst" ]; then
        # Look up which process owns the connection
        proc_info=$(${pkgs.iproute2}/bin/ss -tnp 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep "$dst" \
          | ${pkgs.gawk}/bin/awk '{print $6}' | head -1)
      fi
      if [ -n "$proc_info" ]; then
        msg="Process: $proc_info | $line"
      else
        msg="$line"
      fi
      echo "[$timestamp] [ALERT] $msg" >> "$LOGFILE"
      echo "[ALERT] Tor activity detected: $msg" | ${pkgs.systemd}/bin/systemd-cat -t tor-alert -p warning
      ${pkgs.libnotify}/bin/notify-send -u critical "Tor Activity Detected" "$msg" || true
    done
  '';

  # Periodic scanner: cross-references active connections against Tor IP list
  torConnectionScanScript = pkgs.writeShellScript "tor-connection-scan" ''
    LIST=/var/lib/tor-monitor/exit-nodes.txt
    [ -f "$LIST" ] || exit 0

    mkdir -p ${logDir}
    LOGFILE="${logDir}/tor-scan.log"

    # Get all outbound connections with process info
    ${pkgs.iproute2}/bin/ss -tnp 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR>1 {print $4, $5, $6}' | while read -r local remote proc; do
      ip=$(echo "$remote" | ${pkgs.gnugrep}/bin/grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
      [ -z "$ip" ] && continue
      if ${pkgs.gnugrep}/bin/grep -qFx "$ip" "$LIST"; then
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [TOR-CONN] Process $proc connected to Tor node $ip ($local -> $remote)" >> "$LOGFILE"
        echo "[TOR-CONN] Process $proc connected to Tor node $ip ($local -> $remote)" \
          | ${pkgs.systemd}/bin/systemd-cat -t tor-scan -p warning
        ${pkgs.libnotify}/bin/notify-send -u critical "Tor Connection Found" "Process $proc -> $ip" || true
      fi
    done
  '';
in {
  options.modules.security.tor-monitor = {
    enable = lib.mkEnableOption "Tor network connection monitoring";
  };

  config = lib.mkIf cfg.enable {
    # State directory for IP lists
    systemd.tmpfiles.rules = [
      "d /var/lib/tor-monitor 0700 root root -"
    ];

    # Periodic Tor relay list fetcher
    systemd.services.tor-blocklist-update = {
      description = "Update Tor relay IP blocklist";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = torBlocklistScript;
      };
      wants = ["network-online.target"];
      after = ["network-online.target"];
      path = [pkgs.iptables pkgs.ipset];
    };

    systemd.timers.tor-blocklist-update = {
      description = "Refresh Tor relay list every 6 hours";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        Persistent = true;
      };
    };

    # Real-time alert service (desktop notifications)
    systemd.services.tor-alert = {
      description = "Watch for Tor connection attempts in kernel log";
      serviceConfig = {
        ExecStart = torAlertScript;
        Restart = "always";
        RestartSec = "5s";
        # Run as user for notify-send access
        Environment = "DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus";
      };
      wantedBy = ["multi-user.target"];
      after = ["tor-blocklist-update.service"];
    };

    # Periodic connection scanner — catches established Tor connections with PID
    systemd.services.tor-connection-scan = {
      description = "Scan active connections against Tor relay IP list";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = torConnectionScanScript;
        Environment = "DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus";
      };
      after = ["tor-blocklist-update.service"];
    };

    systemd.timers.tor-connection-scan = {
      description = "Scan for Tor connections every 5 minutes";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "6min";
        OnUnitActiveSec = "5min";
      };
    };

    # Firewall: LOG outbound connections to well-known Tor ports
    networking.firewall.extraCommands = ''
      # Log outbound connections to known Tor ports
      iptables -A OUTPUT -p tcp --dport 9001 -j LOG --log-prefix "[TOR-RELAY] " --log-level 4
      iptables -A OUTPUT -p tcp --dport 9030 -j LOG --log-prefix "[TOR-DIR] " --log-level 4
      iptables -A OUTPUT -p tcp --dport 9050 -j LOG --log-prefix "[TOR-SOCKS] " --log-level 4
      iptables -A OUTPUT -p tcp --dport 9150 -j LOG --log-prefix "[TOR-BROWSER] " --log-level 4
    '';
  };
}
