_: {
  flake.modules.nixos.discovery-monitoring = {
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

      prometheus.scrape "llamacpp" {
        targets = [{
          "__address__" = "100.72.85.73:8080",
          "job"         = "llamacpp",
          "host"        = "orion",
          "server"      = "llama-chat",
        }]
        forward_to      = [prometheus.remote_write.prometheus.receiver]
        scrape_interval = "30s"
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
  };
}
