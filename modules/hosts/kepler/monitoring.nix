_: {
  flake.modules.nixos.kepler-monitoring = {
    environment.etc."alloy/buzz.alloy".text = ''
      prometheus.scrape "buzz_relay" {
        targets = [{
          "__address__" = "127.0.0.1:9102",
          "job"         = "buzz-relay",
          "host"        = "kepler",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }

      prometheus.scrape "postgres_kepler" {
        targets = [{
          "__address__" = "100.94.239.46:9187",
          "job"         = "postgres-kepler",
          "host"        = "kepler",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
      }

    '';
  };
}
