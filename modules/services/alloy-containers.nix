_: {
  flake.modules.nixos.alloy-containers = {
    lib,
    config,
    ...
  }: let
    cfg = config.homelab.alloy;
  in {
    options.homelab.alloy.containerSocket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "unix:///run/user/1000/podman/podman.sock";
      description = ''
        Container runtime socket for the cAdvisor exporter. Set to enable
        per-container metrics (state, cpu, mem, restarts) on a host that runs
        compose stacks. Pairs with m.nixos.alloy (the base config defines the
        prometheus.remote_write.prometheus receiver this block forwards to).
      '';
    };

    options.homelab.alloy.containerdSocket = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Containerd endpoint used by Docker's overlayfs storage driver.";
    };

    options.homelab.alloy.podmanExporter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Scrape prometheus-podman-exporter on loopback.";
    };

    config = lib.mkMerge [
      (lib.mkIf (cfg.containerSocket != null) {
        # cAdvisor inspects runtime sockets, cgroups, and container storage metadata.
        systemd.services.alloy = {
          after = ["docker.service"];
          wants = ["docker.service"];
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "root";
            Group = "root";
          };
        };

        environment.etc."alloy/containers.alloy".text = ''
          prometheus.exporter.cadvisor "containers" {
            docker_host            = "${cfg.containerSocket}"
            ${lib.optionalString (cfg.containerdSocket != null) ''containerd_host        = "${cfg.containerdSocket}"''}
            store_container_labels = true
          }

          prometheus.scrape "container_metrics" {
            targets         = prometheus.exporter.cadvisor.containers.targets
            forward_to      = [prometheus.relabel.container_host.receiver]
            scrape_interval = "30s"
          }

          prometheus.relabel "container_host" {
            rule {
              target_label = "host"
              replacement  = "${config.networking.hostName}"
            }
            forward_to = [prometheus.remote_write.prometheus.receiver]
          }
        '';
      })

      (lib.mkIf cfg.podmanExporter {
        environment.etc."alloy/podman.alloy".text = ''
          prometheus.scrape "podman" {
            targets = [{
              "__address__" = "127.0.0.1:9882",
              "job"         = "podman",
              "host"        = "${config.networking.hostName}",
            }]
            forward_to      = [prometheus.remote_write.prometheus.receiver]
            scrape_interval = "30s"
          }
        '';
      })
    ];
  };
}
