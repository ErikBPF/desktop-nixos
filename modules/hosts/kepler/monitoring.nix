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

    '';
  };
}
