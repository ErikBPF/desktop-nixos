_: {
  flake.modules.nixos.alloy-containers = {
    lib,
    config,
    ...
  }: {
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

    config = lib.mkIf (config.homelab.alloy.containerSocket != null) {
      # Second Alloy config file in the same /etc/alloy dir. The upstream module
      # loads every *.alloy file in configPath (default /etc/alloy) and merges
      # them into one config graph, so this references the base config's
      # prometheus.remote_write.prometheus receiver directly. It also lands in
      # the service's reloadTriggers, so a switch reloads (no restart) on change.
      # Component names (cadvisor "containers", scrape "container_metrics") must
      # not collide with the base config — they don't.
      environment.etc."alloy/containers.alloy".text = ''
        // Container metrics via cAdvisor exporter (host add-on; see
        // modules/services/alloy-containers.nix). Replaces a cAdvisor sidecar.
        prometheus.exporter.cadvisor "containers" {
          docker_host            = "${config.homelab.alloy.containerSocket}"
          store_container_labels = true
        }

        prometheus.scrape "container_metrics" {
          targets         = prometheus.exporter.cadvisor.containers.targets
          forward_to      = [prometheus.remote_write.prometheus.receiver]
          scrape_interval = "30s"
        }
      '';
    };
  };
}
