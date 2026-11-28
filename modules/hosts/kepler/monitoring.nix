_: {
  flake.modules.nixos.kepler-monitoring = {
    environment.etc."alloy/buzz.alloy".text = ''
      prometheus.scrape "postgres_kepler" {
        targets = [{
          "__address__" = "100.90.113.117:9187",
          "job"         = "postgres-kepler",
          "host"        = "kepler",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }

      // goflow2 IPFIX collector metrics. Flow records themselves are discarded;
      // these counters are the only collector output.
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

    '';
  };
}
