_: {
  # Container health as a metric, for the Grafana `containers` rules group.
  # The probe reads live Docker state because cAdvisor's container_health_state
  # is cached at container discovery on the deployed Alloy version.
  flake.modules.nixos.discovery-container-health = {
    config,
    pkgs,
    ...
  }: let
    metricDir = "/var/lib/node-exporter-textfile";
  in {
    systemd.services.container-health = {
      description = "Export per-container Docker health to the textfile collector";
      after = ["docker.service"];
      wants = ["docker.service"];
      path = [pkgs.docker pkgs.coreutils];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash ${./_container-health-probe.sh} ${metricDir} ${config.networking.hostName}";
      };
    };

    systemd.timers.container-health = {
      description = "Publish container health every minute";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "60s";
      };
    };
  };
}
