{config, ...}: {
  flake.modules.nixos.alloy = {
    config,
    lib,
    ...
  }: {
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
    # host-systemd jobs). Rootless compose runs as the fleet user; ownership
    # lets rootless compose (fleet user `erik`) atomically publish gauges while
    # Alloy retains read access.
    systemd.tmpfiles.rules = ["d /var/lib/node-exporter-textfile 0755 erik users - -"];

    environment.etc."alloy/config.alloy".text = ''
      // Grafana Alloy configuration — fleet-wide NixOS module
      // Ships systemd journal logs and host metrics to the Kubernetes backends.

      // ============================================================================
      // Systemd journal logs -> Kubernetes Loki
      // ============================================================================
      loki.source.journal "journal" {
        forward_to = [loki.write.loki.receiver]
        // Hostname is baked in at build time: sys.env("HOSTNAME") is unset in
        // the systemd unit environment, which left the host label EMPTY on all
        // fleet hosts (found 2026-07-03 building the Logs dashboard — journal
        // was one unlabeled fleet-wide stream).
        labels     = { "source" = "journal", "host" = "${config.networking.hostName}" }
      }

      loki.write "loki" {
        endpoint {
          url = "https://loki.homelab.pastelariadev.com/loki/api/v1/push"
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
        // A dead Kepler must not block Discovery/Orion host metrics while the
        // NFS client waits on /mnt/nfs. Preserve Alloy's Linux defaults.
        filesystem {
          mount_points_exclude = "^/(dev|proc|run/credentials/.+|sys|var/lib/docker/.+|mnt/nfs)($|/)"
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
        // AMD GPU busy % + VRAM (node_drm_gpu_busy_percent,
        // node_drm_memory_vram_*) from /sys/class/drm. No-op on hosts without
        // DRM devices; GPU temps stay excluded via the amdgpu chip_exclude
        // above.
        // `systemd` emits node_systemd_unit_state for the failed-unit alert
        // (servarr grafana rule host-systemd-unit-failed) — fleet upgrade
        // hardening RFC P2 (2026-07-12): critical units previously sat failed
        // for hours with zero alerts. Default unit filters (the alert
        // excludes systemd-networkd-wait-online, not the collector). Reads unit
        // state over the system D-Bus, no root needed. Small non-Alloy hosts
        // (voyager/archinaut) get the same metric via node-exporter.nix.
        enable_collectors = ["drm", "systemd"]
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
          instance    = "${config.networking.hostName}",
        }]
        metrics_path    = "/metrics"
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }

      ${lib.optionalString config.services.pangolinNewt.enable ''
        // Pangolin Newt connector health and traffic; bound to loopback only.
        prometheus.scrape "pangolin_newt" {
          targets = [{
            __address__ = "127.0.0.1:2112",
            instance    = "${config.networking.hostName}",
            job         = "pangolin-newt",
          }]
          metrics_path    = "/metrics"
          forward_to      = [prometheus.remote_write.prometheus.receiver]
          scrape_interval = "30s"
        }
      ''}

      // ============================================================================
      // Tailscale client metrics — tailscaled serves Prometheus metrics on the
      // magic IP (local-only, no auth, GA since 1.78). Differentiated value over
      // node_network{device="tailscale0"}: direct-vs-DERP path split on
      // tailscaled_{inbound,outbound}_bytes_total and tailscaled_health_messages.
      // ============================================================================
      prometheus.scrape "tailscale" {
        targets = [{
          __address__ = "100.100.100.100:80",
          // Build-time hostname — sys.env("HOSTNAME") is empty in the unit env
          // (same bug as the journal host label above).
          instance    = "${config.networking.hostName}",
        }]
        metrics_path    = "/metrics"
        forward_to      = [prometheus.relabel.tailscale_keep.receiver]
        scrape_interval = "60s"
      }

      // Keep only the differentiated series named above — the rest of the
      // endpoint duplicates node_network or is static gauges, ~40-60
      // series/host across the fleet for nothing (mirrors the keep-stage
      // discipline of the homelab-gitops in-cluster Alloy).
      prometheus.relabel "tailscale_keep" {
        rule {
          source_labels = ["__name__"]
          regex         = "tailscaled_(inbound|outbound)_(bytes|packets)_total|tailscaled_health_messages"
          action        = "keep"
        }
        forward_to = [prometheus.remote_write.prometheus.receiver]
      }

      // ============================================================================
      // Prometheus remote write -> Kubernetes Prometheus.
      // ============================================================================
      prometheus.remote_write "prometheus" {
        endpoint {
          url = "https://prometheus.homelab.pastelariadev.com/api/v1/write"
        }
      }
    '';
  };
}
