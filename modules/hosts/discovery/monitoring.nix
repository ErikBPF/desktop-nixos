_: {
  flake.modules.nixos.discovery-monitoring = {pkgs, ...}: {
    systemd.services.alloy = {
      after = ["vault-agent.service"];
      wants = ["vault-agent.service"];
    };

    environment.etc."alloy/discovery-apps.alloy".text = ''
      prometheus.scrape "adguard" {
        targets = [{
          "__address__" = "127.0.0.1:9618",
          "job"         = "adguard",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "15s"
      }

      prometheus.scrape "postgres_discovery" {
        targets = [{
          "__address__" = "127.0.0.1:9187",
          "job"         = "postgres-discovery",
          "host"        = "discovery",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "15s"
      }

      prometheus.scrape "cloudflared" {
        targets = [{
          "__address__" = "127.0.0.1:20241",
          "job"         = "cloudflared",
        }]
        forward_to      = [prometheus.relabel.cloudflared_keep.receiver]
        scrape_interval = "60s"
      }

      prometheus.relabel "cloudflared_keep" {
        rule {
          source_labels = ["__name__"]
          regex         = "up|cloudflared_tunnel_.*"
          action        = "keep"
        }
        forward_to = [prometheus.remote_write.prometheus.receiver]
      }

      prometheus.scrape "litellm" {
        targets = [{
          "__address__" = "127.0.0.1:4000",
          "job"         = "litellm",
        }]
        authorization {
          type             = "Bearer"
          credentials_file = "/run/vault-agent/litellm-metrics.token"
        }
        forward_to      = [prometheus.relabel.litellm_drop.receiver]
        scrape_interval = "60s"
      }

      prometheus.relabel "litellm_drop" {
        rule {
          source_labels = ["__name__"]
          regex         = "go_.*|process_.*|python_.*"
          action        = "drop"
        }
        forward_to = [prometheus.remote_write.prometheus.receiver]
      }

      prometheus.scrape "node_vanguard" {
        targets = [{
          "__address__" = "100.90.247.79:9100",
          "job"         = "node-vanguard",
          "host"        = "vanguard",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }

      prometheus.scrape "node_voyager" {
        targets = [{
          "__address__" = "100.105.38.10:9100",
          "job"         = "node-voyager",
          "host"        = "voyager",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }
    '';

    # Strata exposes JSON at /metrics, not Prometheus text. Probe its /health
    # endpoint and publish a textfile metric through the fleet's existing
    # prometheus.exporter.unix textfile collector instead of scraping JSON.
    systemd.services.strata-chat-health-probe = {
      description = "Export Orion Strata chat health as textfile metrics";
      serviceConfig = {
        Type = "oneshot";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ExecStart = pkgs.writeShellScript "strata-chat-health-probe" ''
          set -eu
          healthy=0
          body=$(${pkgs.curl}/bin/curl -fsS -m 10 http://100.72.85.73:8080/health || true)
          case "$body" in
            *'"status": "ok"'*|*'"status":"ok"'*) healthy=1 ;;
          esac
          probed_at=$(${pkgs.coreutils}/bin/date +%s)
          d=/var/lib/node-exporter-textfile
          tmp=$(${pkgs.coreutils}/bin/mktemp "$d/.strata_chat.XXXXXX")
          trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
          {
            echo "# HELP strata_chat_health 1 when the Orion Strata health endpoint reports ok, 0 otherwise."
            echo "# TYPE strata_chat_health gauge"
            echo "strata_chat_health $healthy"
            echo "# HELP strata_chat_health_probe_timestamp_seconds Unix timestamp of the latest Strata health probe."
            echo "# TYPE strata_chat_health_probe_timestamp_seconds gauge"
            echo "strata_chat_health_probe_timestamp_seconds $probed_at"
          } > "$tmp"
          ${pkgs.coreutils}/bin/chmod 0644 "$tmp"
          ${pkgs.coreutils}/bin/mv "$tmp" "$d/strata_chat.prom"
        '';
      };
    };

    systemd.timers.strata-chat-health-probe = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "30s";
      };
    };
  };
}
