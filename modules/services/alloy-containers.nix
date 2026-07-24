_: {
  flake.modules.nixos.alloy-containers = {
    lib,
    config,
    pkgs,
    ...
  }: let
    cfg = config.homelab.alloy;
    socketPath = lib.removePrefix "unix://" cfg.containerSocket;
    socketDir = builtins.dirOf socketPath;
    runtimeDir = builtins.dirOf socketDir;
    rootlessSocket = lib.hasPrefix "/run/user/" socketPath;
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

    options.homelab.alloy.containerSocketGroup = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group allowed to read the configured container runtime socket.";
    };

    config = lib.mkIf (cfg.containerSocket != null) {
      # Grant the alloy service read access to the rootless Podman socket.
      # The upstream module sets SupplementaryGroups = ["systemd-journal"]; NixOS
      # merges list-valued serviceConfig entries across module definitions, so this
      # appends "users" without dropping "systemd-journal". The socket is mode 660
      # owned by erik:users, and alloy runs DynamicUser=yes — without this group
      # the cadvisor exporter gets EACCES on /run/user/1000/podman/podman.sock.
      systemd.services.alloy.serviceConfig = {
        SupplementaryGroups = [cfg.containerSocketGroup];
        ExecStartPre = lib.optionals rootlessSocket [
          "+${pkgs.acl}/bin/setfacl -m g:${cfg.containerSocketGroup}:--x ${runtimeDir} ${socketDir}"
        ];
      };

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
          docker_host            = "${cfg.containerSocket}"
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
    };
  };
}
