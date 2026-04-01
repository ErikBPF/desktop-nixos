_: {
  flake.modules.nixos.alloy = _: {
    services.alloy = {
      enable = true;
      # Bind the Alloy HTTP UI/API to localhost only — it contains pipeline
      # introspection and is not meant to be reachable over Tailscale.
      extraFlags = ["--server.http.listen-addr=127.0.0.1:12345"];
    };

    environment.etc."alloy/config.alloy".text = ''
      // Grafana Alloy configuration — fleet-wide NixOS module
      // Ships systemd journal logs to Discovery Loki, host metrics to Discovery Mimir.
      // Endpoints use Tailscale MagicDNS ("discovery") — requires tailscaled running.

      // ============================================================================
      // Systemd journal logs -> Loki (on Discovery via Tailscale)
      // ============================================================================
      loki.source.journal "journal" {
        forward_to = [loki.write.loki.receiver]
        labels     = { "source" = "journal", "host" = sys.env("HOSTNAME") }
      }

      loki.write "loki" {
        endpoint {
          url = "http://100.76.140.121:3100/loki/api/v1/push"
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
      // Alloy self-metrics — pipeline health, component counts, queue depths
      // ============================================================================
      prometheus.scrape "alloy_self" {
        targets = [{
          __address__ = "127.0.0.1:12345",
        }]
        metrics_path    = "/metrics"
        forward_to      = [prometheus.remote_write.mimir.receiver]
        scrape_interval = "30s"
      }

      // ============================================================================
      // Prometheus remote write -> Discovery Mimir (via Tailscale)
      // ============================================================================
      prometheus.remote_write "mimir" {
        endpoint {
          url = "http://100.76.140.121:9009/api/v1/push"
        }
      }
    '';
  };
}
