# Self-hosted NetBird control plane on discovery — WP2 of the NetBird
# implementation plan.
#
#   plan:   docs/proposals/2026-07-10-netbird-implementation-plan.md (WP2)
#   design: docs/proposals/2026-07-10-netbird-selfhosted-overlay.md
#           §3 (components), §4 (placement), §5 (exposure), §6 (security),
#           §8 (IaC split), §9 (secrets); rulings §11 Q1/Q2/Q3/Q5/Q9
#
# Q1/Q2: Docker oci-containers, not rootless podman and not nixpkgs'
# `services.netbird.server` — discovery is rootful Docker (see
# modules/hosts/discovery/containers.nix), and the Coturn-era nixpkgs module
# doesn't expose the native WS/QUIC relay + PocketID + combined-server layout
# this RFC assumes. Client peers still use the nixpkgs `services.netbird.clients`
# module (separate, WP1).
#
# DISABLED BY DEFAULT (services.netbirdServer.enable = false). Every value below
# is either a public/non-secret fact (fleet.netbird.*, modules/meta.nix) or a
# sops-secret PLACEHOLDER key that does not yet exist in secrets/sops/secrets.yaml
# — minting the real values is Phase S (human-gated, see the implementation
# plan). Because all of it sits under `lib.mkIf cfg.enable`, none of it
# evaluates while disabled: `just dry discovery` stays a clean no-op even
# though the sops keys referenced below don't exist yet, and even though
# discovery's `default.nix` imports this module.
#
# HONEST CAVEAT (mirrors §8's own "verify against the pin at build time"):
# NetBird's self-hosted config surface has moved more than once (v0.29 relay,
# v0.65 combined server) and its exact env-var/JSON-field names couldn't be
# fully confirmed offline. Every genuinely uncertain field is flagged with a
# Phase-O TODO; a wrong guess here fails LOUD (container won't start / relay
# logs an auth error), not silently insecure.
{
  config,
  self,
  ...
}: let
  inherit (config) username;
  nb = config.flake.fleet.netbird; # managementUrl, overlayCidr, dnsDomain, relayHosts
  ingressZone = config.flake.fleet.ingress.homelab.zone; # "homelab.pastelariadev.com"
  idUrl = "https://id.${ingressZone}";
in {
  flake.modules.nixos.discovery-netbird-server = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.netbirdServer;
    sopsFile = self + "/secrets/sops/secrets.yaml";
    dataDir = "/home/${username}/homelab/apps/netbird"; # mirrors discovery-hermes-oci's hostDataDir convention

    # Image tags — current stable as of 2026-07-10 (checked docs.netbird.io,
    # Docker Hub tag lists, and the pocket-id GitHub releases page; no digest
    # verification performed, per task scope).
    # TODO(Phase-O): mirror through Harbor + pin digest (§8 red-team supply-chain
    # note — the control plane sees every peer public key and mints tokens).
    netbirdTag = "0.74.3"; # netbirdio/{management,signal,relay} share one release train
    dashboardTag = "v2.90.3"; # netbirdio/dashboard versions independently
    pocketIdTag = "v2.10.0";

    # discovery's own relay ("relay#1", §3/§4) is reached over the tailnet/LAN
    # only, behind SWAG under the existing wildcard cert (§5 "Relay TLS (Q3,
    # ruled)" — only the voyager/public relay needs its own LE cert). Distinct
    # from the two PUBLIC voyager/2nd-VM relay hostnames in nb.relayHosts
    # (Cloudflare DNS-only, WP3 — not stood up yet, but harmless to list here:
    # clients simply won't reach them until WP3 ships).
    relay1Fqdn = "nb-relay.${ingressZone}";
    relay1Port = 33080; # native relay port behind the reverse proxy (RFC §3 port table)

    # Non-secret management config: external STUN only (Q9 — no self-hosted
    # reflector), and the relay list (built-in relay#1 + the two public
    # relayHosts from the fleet.netbird SSOT). CredentialsTTL raised from the
    # 24h default to 168h (7d) per §7, widening the reconnect-survival window
    # for a control-plane outage. The shared relay HMAC (`Secret`) is
    # deliberately NOT a literal value here — see the comment on
    # netbird-management's environment below.
    managementConfig = pkgs.writeText "netbird-management.json" (builtins.toJSON {
      StoreConfig.Engine = "postgres";
      Stuns = [
        {
          Proto = "udp";
          URI = "stun:stun.netbird.io:3478";
          Username = "";
          Password = null;
        }
        {
          # Fallback external STUN (Q9) — Google's public STUN, widely used and
          # free; lowest-sensitivity possible dependency (a STUN server only
          # echoes back the caller's public IP:port).
          Proto = "udp";
          URI = "stun:stun.l.google.com:19302";
          Username = "";
          Password = null;
        }
      ];
      Relay = {
        Addresses =
          ["rels://${relay1Fqdn}:443"]
          ++ map (h: "rels://${h}:443") nb.relayHosts;
        CredentialsTTL = "168h";
        # TODO(Phase-O): verify netbird's config loader actually expands
        # "$NB_AUTH_SECRET" inside a JSON string (some Go config loaders do
        # env-expansion on load, some don't). NB_AUTH_SECRET is ALSO set as a
        # real container env var below as a second attempt. If neither works,
        # this field must move to a config file rendered at activation time
        # (envsubst from the sops secret into a RuntimeDirectory path) instead
        # of this static, Nix-store-readable file — a real secret must never
        # be baked into a writeText derivation.
        Secret = "\$NB_AUTH_SECRET";
      };
    });
  in {
    options.services.netbirdServer = {
      enable = lib.mkEnableOption "self-hosted NetBird control plane (management/signal/dashboard/PocketID/relay#1) on discovery — disabled by default, see the NetBird RFC (Phase S/O are human-gated)";
    };

    config = lib.mkIf cfg.enable {
      # Q1: discovery force-disables podman (see discovery-containers.nix) and
      # oci-containers defaults to "podman" on stateVersion >= 22.05 — must be
      # set explicitly or these containers silently try (and fail) to use a
      # backend that's off.
      virtualisation.oci-containers.backend = "docker";

      # --- Secrets (Phase S mints the real values; placeholders only) --------
      # Single-purpose dotenv-style secrets, same shape as
      # discovery-hermes-oci.nix's `hermes_agent/server_env` — sops-nix drops
      # the decrypted scalar verbatim to `path`; docker's `environmentFiles`
      # reads it as KEY=VALUE lines.
      sops.secrets."netbird/postgres_dsn" = {
        inherit sopsFile;
        format = "yaml";
        key = "netbird/postgres_dsn";
        mode = "0400";
        path = "/run/secrets/netbird-postgres-dsn";
        # Q5: reuse discovery's infra Postgres (the `postgres` container on
        # homelab-net) rather than a dedicated instance. Content is the FULL
        # DSN line, e.g.:
        #   NETBIRD_STORE_ENGINE_POSTGRES_DSN=postgresql://netbird:<pw>@postgres:5432/netbird?sslmode=disable
        # TODO(Phase-O, servarr repo): provision the `netbird` role + database
        # in discovery's infra Postgres (scripts/provision-db.sql) before this
        # DSN is real.
        restartUnits = ["docker-netbird-management.service"];
      };
      sops.secrets."netbird/auth_secret" = {
        inherit sopsFile;
        format = "yaml";
        key = "netbird/auth_secret";
        mode = "0400";
        path = "/run/secrets/netbird-auth-secret";
        # Content: `NB_AUTH_SECRET=<openssl rand -base64 32>` (§6b-H7 — must be
        # IDENTICAL on management and every relay; mismatch fails silently at
        # the relay, so verify a real peer connection in Phase-O §10-2).
        restartUnits = ["docker-netbird-management.service" "docker-netbird-relay.service"];
      };
      sops.secrets."netbird/oidc_client_secret" = {
        inherit sopsFile;
        format = "yaml";
        key = "netbird/oidc_client_secret";
        mode = "0400";
        path = "/run/secrets/netbird-oidc-client-secret";
        # Content: `NETBIRD_AUTH_CLIENT_SECRET=<value>` — the confidential
        # client secret PocketID issues once an OIDC client for NetBird is
        # registered there (Phase-O: "PocketID first-run + passkey enrol").
        # Only management needs it; the dashboard SPA uses the public/PKCE
        # side of the same client (no secret in browser-shipped code).
        restartUnits = ["docker-netbird-management.service"];
      };
      sops.secrets."netbird/pocketid_jwt_key" = {
        inherit sopsFile;
        format = "yaml";
        key = "netbird/pocketid_jwt_key";
        mode = "0400";
        path = "/run/secrets/netbird-pocketid-jwt-key";
        # Content: `ENCRYPTION_KEY=<value>` — PocketID's at-rest encryption key
        # for its stored JWT signing keys (§6/§9 "JWT signing"). TODO(Phase-O):
        # confirm the exact env var name against pocket-id's current docs
        # before first switch.
        restartUnits = ["docker-netbird-pocketid.service"];
      };

      virtualisation.oci-containers.containers = {
        netbird-management = {
          image = "netbirdio/management:${netbirdTag}";
          volumes = [
            "${managementConfig}:/etc/netbird/management.json:ro"
            "${dataDir}/management:/var/lib/netbird"
          ];
          cmd = [
            "--port"
            "443"
            "--log-file"
            "console"
            "--log-level"
            "info"
            "--disable-anonymous-metrics=true"
            "--dns-domain=${nb.dnsDomain}"
          ];
          environment = {
            # Q5: store engine is postgres, not the SQLite default.
            NETBIRD_STORE_ENGINE = "postgres";
            # OIDC bootstrap wiring for the initial (PocketID) identity
            # provider. Beyond this bootstrap set, ongoing identity-provider
            # config is a WP4/homelab-iac concern (the netbirdio/netbird
            # Terraform provider's `identity_provider` resource, §8) — not
            # re-declared here.
            NETBIRD_AUTH_CLIENT_ID = "netbird"; # TODO(Phase-O): replace with the real PocketID client ID once created
            NETBIRD_AUTH_AUTHORITY = idUrl;
            NETBIRD_AUTH_AUDIENCE = "netbird";
            NETBIRD_USE_AUTH0 = "false";
          };
          # NB_AUTH_SECRET (the best-effort second attempt at the relay HMAC,
          # see managementConfig.Relay.Secret above) arrives via this file, not
          # a literal `environment` entry — a literal `-e NB_AUTH_SECRET=`
          # would risk clobbering the real value depending on docker's
          # env/env-file precedence.
          environmentFiles = [
            config.sops.secrets."netbird/postgres_dsn".path
            config.sops.secrets."netbird/auth_secret".path
            config.sops.secrets."netbird/oidc_client_secret".path
          ];
          # No published host ports: SWAG (servarr) reaches this by container
          # name over homelab-net, same ingress model as discovery-hermes-oci.
          networks = ["homelab-net"];
        };

        netbird-signal = {
          image = "netbirdio/signal:${netbirdTag}";
          cmd = ["--port" "80" "--log-file" "console"];
          networks = ["homelab-net"];
        };

        netbird-dashboard = {
          image = "netbirdio/dashboard:${dashboardTag}";
          environment = {
            NETBIRD_MGMT_API_ENDPOINT = nb.managementUrl;
            NETBIRD_MGMT_GRPC_API_ENDPOINT = nb.managementUrl;
            AUTH_AUTHORITY = idUrl;
            AUTH_CLIENT_ID = "netbird"; # TODO(Phase-O): same PocketID client ID as management
            AUTH_SUPPORTED_SCOPES = "openid profile email";
            AUTH_AUDIENCE = "netbird";
            USE_AUTH0 = "false";
          };
          networks = ["homelab-net"];
        };

        netbird-pocketid = {
          image = "ghcr.io/pocket-id/pocket-id:${pocketIdTag}";
          volumes = ["${dataDir}/pocket-id:/app/data"];
          environment = {
            APP_URL = idUrl;
            TRUST_PROXY = "true"; # behind SWAG (§5 — tailnet/LAN-only ingress)
          };
          environmentFiles = [
            config.sops.secrets."netbird/pocketid_jwt_key".path
          ];
          networks = ["homelab-net"];
        };

        netbird-relay = {
          # "relay#1" (§3/§4): the discovery-side, tailnet/LAN-only relay.
          # Distinct from the voyager/public relay (WP3, netbird-relay.nix,
          # not this module).
          image = "netbirdio/relay:${netbirdTag}";
          environment = {
            NB_LISTEN_ADDRESS = ":${toString relay1Port}";
            NB_EXPOSED_ADDRESS = "rels://${relay1Fqdn}:443"; # reached via SWAG on 443, not the raw container port
            # NB_ENABLE_STUN left unset → defaults false (Q9/§6b-H1: no
            # self-hosted STUN reflector, ever, on any relay in this design).
          };
          environmentFiles = [
            config.sops.secrets."netbird/auth_secret".path
          ];
          networks = ["homelab-net"];
        };
      };

      # No host firewall rules here: nothing is published to the host
      # (no `ports` on any container above), and docker would bypass the
      # nixos firewall anyway. SWAG over homelab-net is the only ingress —
      # matching §5 (tailnet/LAN-only control plane, zero new public surface
      # on discovery; the only public surface in the whole RFC is the
      # voyager relay, WP3).

      # TODO(Phase-O, servarr repo): SWAG proxy-conf for nb.<zone> (dashboard +
      # management, HTTP/2 + gRPC passthrough) and id.<zone> (pocket-id), plus
      # an internal-only vhost for relay1Fqdn (nb-relay.<zone>) proxying to
      # netbird-relay:33080 — see docs/implemented/... servarr flow
      # (references/repos/servarr/machines/discovery/networking.yml).

      # TODO(Phase-O, homelab-iac repo): add the Tailscale ACL rule
      # restricting nb.<zone>/id.<zone> (discovery :443) to admin devices only
      # (RFC §6 "Control-plane reachability is gated, not flat-trusted") —
      # same shape as the existing admin-SSH rule in tailscale/acl.
    };
  };
}
