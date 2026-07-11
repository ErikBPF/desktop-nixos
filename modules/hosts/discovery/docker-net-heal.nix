# Self-heal for containers that lose their `homelab-net` attachment at boot.
#
# Observed 2026-07-11: the `adguard` container came up detached from the
# external `homelab-net` (NetworkSettings.Networks == {}), while its
# HostConfig.NetworkMode still named homelab-net. Effect: SWAG could not resolve
# the `adguard` upstream (502 on adguard.homelab.*) AND the host port publishes
# (:53/:3000/:8090) never bound — a networkless container can't DNAT its ports.
#
# Root cause is a dockerd boot race: compose services carry
# `restart: unless-stopped`, so dockerd auto-restarts them from persisted state
# before the user `podman-compose-*` units run. When a container is restarted
# before/without the external network being (re)joined it ends up detached, and
# the later `docker-compose up -d` sees a matching config hash and skips the
# recreate — so the detach persists across the boot-time compose run. A manual
# `docker network connect` re-establishes both the endpoint and the port NAT.
#
# This heals exactly that signature: any running container whose primary
# NetworkMode is `homelab-net` but which is not actually attached is reconnected.
# It fires nothing on healthy containers (the check only matches the detached
# ones), so it is safe to run fleet-wide on the timer.
#
# Host-only module (dendritic contract: `<host>-<capability>`). Promote to a
# reusable module if another Docker host grows the same external-network setup.
_: {
  flake.modules.nixos.discovery-docker-net-heal = {pkgs, ...}: {
    systemd.services.docker-net-heal = {
      description = "Reconnect containers that dropped off homelab-net";
      after = ["docker.service"];
      wants = ["docker.service"];
      path = [pkgs.docker pkgs.gnugrep pkgs.coreutils];
      serviceConfig = {
        Type = "oneshot";
        SyslogIdentifier = "docker-net-heal";
      };
      script = ''
        set -uo pipefail
        docker network inspect homelab-net >/dev/null 2>&1 || {
          echo "homelab-net absent — nothing to heal yet"
          exit 0
        }
        docker ps --format '{{.Names}}' | while read -r c; do
          [ -n "$c" ] || continue
          mode=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$c" 2>/dev/null || echo "")
          [ "$mode" = "homelab-net" ] || continue
          nets=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$c" 2>/dev/null || echo "")
          if ! echo "$nets" | grep -qw homelab-net; then
            echo "$c: NetworkMode=homelab-net but endpoint missing — reconnecting"
            if docker network connect homelab-net "$c"; then
              echo "$c: reconnected to homelab-net"
            else
              echo "$c: FAILED to reconnect (will retry next tick)"
            fi
          fi
        done
      '';
    };

    systemd.timers.docker-net-heal = {
      description = "Run docker-net-heal shortly after boot and every 2 min";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitActiveSec = "2min";
        AccuracySec = "10s";
      };
    };
  };
}
