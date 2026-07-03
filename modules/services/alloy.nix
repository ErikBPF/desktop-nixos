_: {
  flake.modules.nixos.alloy = _: {
    services.alloy = {
      enable = true;
      # Bind the Alloy HTTP UI/API to localhost only — it contains pipeline
      # introspection and is not meant to be reachable over Tailscale.
      # --disable-reporting stops the anonymous usage pings to stats.grafana.org.
      extraFlags = [
        "--server.http.listen-addr=127.0.0.1:12345"
        "--disable-reporting"
      ];
    };

    # Restart policy: upstream NixOS module already sets Restart=always.
    systemd.services.alloy.serviceConfig.TimeoutStopSec = "1s";

    # Textfile-collector drop dir: host cron/batch jobs write <job>.prom here on
    # success (e.g. `<job>_last_success_seconds <epoch>`), the unix exporter
    # surfaces it, and Grafana alerts on staleness — a declarative dead-man's
    # switch in the metrics pipeline (replaces self-hosted Healthchecks for
    # host-systemd jobs). 0755 so the alloy user can read what root-run jobs write.
    systemd.tmpfiles.rules = ["d /var/lib/node-exporter-textfile 0755 root root - -"];

    environment.etc."alloy/config.alloy".text = ''
      // Grafana Alloy configuration — fleet-wide NixOS module
      // Ships systemd journal logs to Discovery Loki, host metrics to Discovery Prometheus.
      // Endpoints use Discovery's MagicDNS name ("discovery") — requires tailscaled
      // + accept-dns (fleet default). Tailnet ACL grants <host> -> discovery:3100,9090.

      // ============================================================================
      // Systemd journal logs -> Loki (on Discovery via Tailscale)
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
      prometheus.exporter.unix "host" {
        // Dead-man's-switch source: jobs write <job>_last_success_seconds to a
        // .prom file in this dir on success; Grafana alerts when it goes stale.
        textfile {
          directory = "/var/lib/node-exporter-textfile"
        }
        // An amdgpu SMU firmware hang leaves hwmon sysfs reads blocked in
        // uninterruptible D-state; NodeCollector.Collect waits on every
        // collector, so one wedged read killed ALL host metrics on orion
        // (2026-07-02, up==0 while the host was fine). Excluding the amdgpu
        // chip caps the blast radius to GPU temps; CPU/board sensors still
        // report. No-op on hosts without an AMD GPU.
        hwmon {
          chip_exclude = "amdgpu"
        }
      }

      prometheus.scrape "host_metrics" {
        targets         = prometheus.exporter.unix.host.targets
        forward_to      = [prometheus.remote_write.prometheus.receiver]
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
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }

      // ============================================================================
      // Tailscale client metrics — tailscaled serves Prometheus metrics on the
      // magic IP (local-only, no auth, GA since 1.78). Differentiated value over
      // node_network{device="tailscale0"}: direct-vs-DERP path split on
      // tailscaled_{inbound,outbound}_bytes_total and tailscaled_health_messages.
      // ============================================================================
      prometheus.scrape "tailscale" {
        targets = [{
          __address__ = "100.100.100.100:80",
          instance    = sys.env("HOSTNAME"),
        }]
        metrics_path    = "/metrics"
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "60s"
      }

      // ============================================================================
      // Prometheus remote write -> Discovery Prometheus (via Tailscale).
      // :9090/api/v1/write, --web.enable-remote-write-receiver enabled on the
      // Prometheus container (servarr discovery/monitoring.yml). The old :9009
      // target was Mimir, which was never deployed — host metrics never shipped.
      // ============================================================================
      prometheus.remote_write "prometheus" {
        endpoint {
          url = "http://discovery:9090/api/v1/write"
        }
      }
    '';
  };
}
