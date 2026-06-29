# SWAG cert / ingress liveness probe. The 2026-06-29 outage was silent: SWAG's
# Let's Encrypt cert had failed to (re)mint and nothing noticed until a
# subdomain returned 000. This probes the cert SWAG actually serves on :443 —
# one daily TLS handshake against a canary subdomain on the wildcard cert. A
# failed handshake means SWAG is down or has no cert (connect refused / TLS
# error); a near-future notAfter means renewal has been failing. Either way it
# fires an ntfy alert before a user hits a dead subdomain. See
# docs/proposals/2026-06-29-discovery-resilience-fixes.md (P0-1).
_: {
  flake.modules.nixos.swag-cert-monitor = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.swagCertMonitor;
  in {
    options.services.swagCertMonitor = {
      enable = lib.mkEnableOption "daily SWAG cert/ingress liveness probe with ntfy alert";

      ntfyUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "ntfy topic URL for cert alerts (empty = log only).";
      };

      host = lib.mkOption {
        type = lib.types.str;
        description = ''
          Canary subdomain (SNI) covered by SWAG's wildcard cert. The probe
          opens a TLS handshake to 127.0.0.1:443 with this SNI and reads the
          served leaf cert's notAfter.
        '';
      };

      warnDays = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Alert when the served leaf cert expires in fewer than this many days (LE certs renew at 30d left, so <14d means renewal has been failing for two weeks).";
      };
    };

    config = lib.mkIf cfg.enable {
      systemd.services.swag-cert-monitor = {
        description = "Probe SWAG's served cert on :443 and alert via ntfy on failure/expiry";
        # Needs the host network up; SWAG is a container so don't hard-order on it.
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          # Read-only, no privileges needed beyond loopback TCP.
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
          ExecStart = pkgs.writeShellScript "swag-cert-monitor" ''
            set -uo pipefail
            HOST=${lib.escapeShellArg cfg.host}
            NTFY=${lib.escapeShellArg cfg.ntfyUrl}

            alert() { # $1=title $2=priority $3=tags $4=body
              echo "$4"
              [ -n "$NTFY" ] && ${pkgs.curl}/bin/curl -s \
                -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
                -d "$4" "$NTFY" >/dev/null || true
            }

            # Pull the served leaf cert via a real TLS handshake on the path
            # users hit. Empty enddate ⇒ handshake failed ⇒ SWAG down / no cert.
            ENDDATE=$(echo | ${pkgs.openssl}/bin/openssl s_client \
              -connect 127.0.0.1:443 -servername "$HOST" 2>/dev/null \
              | ${pkgs.openssl}/bin/openssl x509 -noout -enddate 2>/dev/null \
              | cut -d= -f2)

            if [ -z "$ENDDATE" ]; then
              alert "SWAG ingress DOWN on ${config.networking.hostName}" "urgent" "rotating_light" \
                "TLS handshake to 127.0.0.1:443 (SNI $HOST) failed — SWAG is down or has no cert. Check: docker logs swag; docker exec swag ls /config/etc/letsencrypt/live/"
              exit 0
            fi

            END_EPOCH=$(${pkgs.coreutils}/bin/date -d "$ENDDATE" +%s 2>/dev/null)
            NOW=$(${pkgs.coreutils}/bin/date +%s)
            if [ -z "$END_EPOCH" ]; then
              alert "SWAG cert unparseable on ${config.networking.hostName}" "high" "warning" \
                "Got a cert from SWAG but could not parse notAfter ('$ENDDATE')."
              exit 0
            fi

            DAYS=$(( (END_EPOCH - NOW) / 86400 ))
            if [ "$DAYS" -lt ${toString cfg.warnDays} ]; then
              alert "SWAG cert expiring in $DAYS d on ${config.networking.hostName}" "high" "warning" \
                "Served leaf cert for $HOST expires $ENDDATE ($DAYS days). LE renews at 30d left — renewal is failing. Check certbot DNS-01 / cloudflare token."
            else
              echo "SWAG cert OK: $HOST valid $DAYS more days (notAfter $ENDDATE)"
            fi
          '';
        };
      };

      systemd.timers.swag-cert-monitor = {
        description = "Daily SWAG cert/ingress liveness probe";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*-*-* 08:00:00";
          Persistent = true;
          RandomizedDelaySec = "15m";
        };
      };
    };
  };
}
