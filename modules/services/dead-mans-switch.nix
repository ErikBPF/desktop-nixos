# External dead-man's-switch (R2, docs/proposals/2026-07-10-vanguard-second-oracle-node.md).
# Grafana->Discord alerting runs INSIDE the home — a whole-home/ISP outage
# today yields silence, not an alert. This is an offsite prober (intended
# host: vanguard) that checks the home fleet's reachability from outside and
# POSTs to an INDEPENDENT Discord webhook (its own, not the in-home
# discord_webhook_incidents) if the fleet stays silent past a threshold.
# Deliberately a plain systemd timer + shell script, not a Prometheus/
# blackbox_exporter stack — proportionate to a 1 GB host and to what's asked.
#
# DISABLED BY DEFAULT (services.deadMansSwitch.enable = false).
{
  self,
  config,
  ...
}: let
  fleet = config.flake.fleet;
in {
  flake.modules.nixos.dead-mans-switch = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.deadMansSwitch;
    sopsFile = self + "/secrets/sops/secrets.yaml";
    webhookPath = config.sops.secrets."dead-mans-switch/discord_webhook".path;

    probeScript = pkgs.writeShellScript "dead-mans-switch-probe" ''
      set -euo pipefail
      STATE=/var/lib/dead-mans-switch/failures
      [ -f "$STATE" ] || echo 0 > "$STATE"

      if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 10 -o /dev/null "${cfg.checkUrl}"; then
        echo 0 > "$STATE"
        exit 0
      fi

      failures=$(($(cat "$STATE") + 1))
      echo "$failures" > "$STATE"
      echo "dead-mans-switch: probe of ${cfg.checkUrl} failed ($failures/${toString cfg.failureThreshold})" >&2

      if [ "$failures" -eq ${toString cfg.failureThreshold} ]; then
        webhook=$(cat "${webhookPath}")
        ${pkgs.curl}/bin/curl --silent --max-time 10 -X POST -H 'Content-Type: application/json' \
          --data "{\"content\": \"vanguard dead-man's-switch: ${cfg.checkUrl} unreachable for $failures consecutive checks — the home fleet may be dark.\"}" \
          "$webhook" || true
      fi
    '';
  in {
    options.services.deadMansSwitch = {
      enable = lib.mkEnableOption "the offsite dead-man's-switch prober — disabled by default, see docs/proposals/2026-07-10-vanguard-second-oracle-node.md §R2";

      checkUrl = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "https://${fleet.ingress.homelab.zone}";
        description = "Endpoint probed from outside the home to detect a whole-fleet outage.";
      };

      interval = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "5m";
        description = "How often to probe (systemd OnUnitActiveSec/OnBootSec).";
      };

      failureThreshold = lib.mkOption {
        type = lib.types.int;
        default = 6; # 6 * 5m = 30 min of silence before alerting
        description = "Consecutive failed probes before posting to Discord (fires once per outage, resets on the next success).";
      };
    };

    config = lib.mkIf cfg.enable {
      # TODO(before enable): this key does not exist in secrets/sops/secrets.yaml
      # yet — add an INDEPENDENT Discord webhook (its own channel, not the
      # in-home `discord_webhook_incidents`) before flipping this role on, same
      # placeholder pattern as netbird/auth_secret (modules/hosts/voyager/
      # netbird-relay.nix).
      sops.secrets."dead-mans-switch/discord_webhook" = {
        inherit sopsFile;
        format = "yaml";
        key = "dead-mans-switch/discord_webhook";
        mode = "0400";
      };

      systemd.services.dead-mans-switch = {
        description = "Offsite dead-man's-switch: probe the home fleet, alert on prolonged silence";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${probeScript}";
          StateDirectory = "dead-mans-switch";
        };
      };

      systemd.timers.dead-mans-switch = {
        description = "Timer for the offsite dead-man's-switch probe";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = cfg.interval;
          OnUnitActiveSec = cfg.interval;
        };
      };
    };
  };
}
