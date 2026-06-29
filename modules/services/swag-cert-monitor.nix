# SWAG cert / ingress liveness probe. The 2026-06-29 outage was silent: SWAG's
# Let's Encrypt cert had failed to (re)mint and nothing noticed until a
# subdomain returned 000. This probes the cert SWAG actually serves on :443 —
# one daily TLS handshake against a canary subdomain on the wildcard cert.
#
# It checks three failure modes, each of which alerts to Discord:
#   1. handshake fails       → SWAG is down / no cert at all
#   2. issuer is not LE       → SWAG fell back to its self-signed cert because
#                               the LE mint failed (this is the silent-outage
#                               trap: a self-signed cert has a far-future expiry,
#                               so checking notAfter alone reads as healthy)
#   3. notAfter < warnDays    → renewal has been failing
#
# Alerting goes to a Discord webhook, NOT ntfy: ntfy on this host rides SWAG
# (ntfy.homelab → SWAG proxy), so a "SWAG is down" alert could never leave the
# box. Discord is off-host (discord.com) — it only needs outbound DNS (public
# fallback resolver), not the local ingress it is monitoring. See
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
      enable = lib.mkEnableOption "daily SWAG cert/ingress liveness probe with Discord alert";

      discordWebhookFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Path to a file containing the Discord webhook URL for alerts (read at
          runtime so the secret never enters the Nix store). Empty = log only.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        description = ''
          Canary subdomain (SNI) covered by SWAG's wildcard cert. The probe
          opens a TLS handshake to 127.0.0.1:443 with this SNI and reads the
          served leaf cert's notAfter + issuer.
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
        description = "Probe SWAG's served cert on :443 and alert to Discord on failure/expiry";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          # Read-only, no privileges needed beyond outbound TCP. ProtectSystem
          # keeps /etc (CA bundle) readable so curl can reach https://discord.com.
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
          ExecStart = pkgs.writeShellScript "swag-cert-monitor" ''
            set -uo pipefail
            HOST=${lib.escapeShellArg cfg.host}
            WEBHOOK_FILE=${lib.escapeShellArg cfg.discordWebhookFile}

            alert() { # $1=message (markdown)
              echo "$1"
              [ -n "$WEBHOOK_FILE" ] && [ -r "$WEBHOOK_FILE" ] || return 0
              ${pkgs.curl}/bin/curl -fsS -m 10 -H "Content-Type: application/json" \
                --data "$(${pkgs.jq}/bin/jq -nc --arg c "$1" '{content:$c}')" \
                "$(cat "$WEBHOOK_FILE")" >/dev/null || true
            }

            # Pull the served leaf cert via a real TLS handshake on the path
            # users hit. Empty ⇒ handshake failed ⇒ SWAG down / no cert.
            CERT=$(echo | ${pkgs.openssl}/bin/openssl s_client \
              -connect 127.0.0.1:443 -servername "$HOST" 2>/dev/null \
              | ${pkgs.openssl}/bin/openssl x509 -noout -enddate -issuer 2>/dev/null)

            if [ -z "$CERT" ]; then
              alert "🔴 **SWAG ingress DOWN** on ${config.networking.hostName} — TLS handshake to :443 (SNI $HOST) failed. SWAG is down or has no cert. Check: \`docker logs swag\`"
              exit 0
            fi

            ISSUER=$(printf '%s\n' "$CERT" | sed -n 's/^issuer=//p')
            ENDDATE=$(printf '%s\n' "$CERT" | sed -n 's/^notAfter=//p')

            # Issuer guard: when LE mint fails, SWAG serves a self-signed cert
            # (far-future expiry → notAfter alone reads healthy). Real cert is
            # issued by Let's Encrypt; anything else means the mint failed.
            case "$ISSUER" in
              *"Let's Encrypt"*) : ;;
              *)
                alert "🔴 **SWAG serving NON-LE cert** on ${config.networking.hostName} — issuer: \`$ISSUER\`. LE mint failed; SWAG fell back to a self-signed cert. Check certbot DNS-01 / cloudflare token."
                exit 0
                ;;
            esac

            END_EPOCH=$(${pkgs.coreutils}/bin/date -d "$ENDDATE" +%s 2>/dev/null)
            if [ -z "$END_EPOCH" ]; then
              alert "🟠 **SWAG cert unparseable** on ${config.networking.hostName} — notAfter='$ENDDATE'."
              exit 0
            fi
            NOW=$(${pkgs.coreutils}/bin/date +%s)
            DAYS=$(( (END_EPOCH - NOW) / 86400 ))
            if [ "$DAYS" -lt ${toString cfg.warnDays} ]; then
              alert "🟠 **SWAG cert expiring in $DAYS d** on ${config.networking.hostName} — $HOST notAfter $ENDDATE. LE renews at 30d left; renewal is failing."
            else
              echo "SWAG cert OK: $HOST valid $DAYS more days (issuer $ISSUER, notAfter $ENDDATE)"
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
