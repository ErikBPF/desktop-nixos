_: {
  flake.modules.nixos.alloy = _: {
    services.alloy.enable = true;

    environment.etc."alloy/config.alloy".text = ''
      // Grafana Alloy configuration — fleet-wide NixOS module
      // Ships systemd journal logs to Discovery Loki, host metrics to Discovery Mimir via Tailscale

      // ============================================================================
      // Systemd journal logs -> Loki (on Discovery)
      // ============================================================================
      loki.source.journal "journal" {
        forward_to = [loki.write.loki.receiver]
        labels     = { "source" = "journal", "host" = sys.env("HOSTNAME") }
      }

      loki.write "loki" {
        endpoint {
          url = "http://discovery:3100/loki/api/v1/push"
        }
      }

      // ============================================================================
      // Host metrics (native NixOS — no path overrides needed)
      // ============================================================================
      prometheus.exporter.unix "host" {}

      prometheus.scrape "host_metrics" {
        targets         = prometheus.exporter.unix.host.targets
        forward_to      = [prometheus.remote_write.mimir.receiver]
        scrape_interval = "30s"
      }

      // ============================================================================
      // Prometheus remote write -> Discovery Mimir
      // ============================================================================
      prometheus.remote_write "mimir" {
        endpoint {
          url = "http://discovery:9009/api/v1/push"
        }
      }
    '';
  };
}
