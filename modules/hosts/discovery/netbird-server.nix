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

    # PocketID OIDC client for NetBird — public client + PKCE (RFC §5 / G4), so
    # there is NO client secret; this ID is public (shipped in the dashboard SPA)
    # and is BOTH the client_id and the audience. Minted in PocketID's admin UI
    # (Administration -> OIDC Clients -> "NetBird"), captured 2026-07-11.
    oidcClientId = "579d2f64-2bd0-4c5d-9796-f5a4ba2268d0";

    # Management config. The netbird management BINARY reads concrete values
    # from this JSON (the upstream getting-started envsubst's a template BEFORE
    # the binary sees it — the binary does NOT expand env vars in the JSON), so
    # every value here is literal. Auth/OIDC lives in HttpConfig + the flow
    # blocks (NOT in container env — those NETBIRD_AUTH_* names are the
    # getting-started's templating vars, not runtime config). Schema verified
    # against netbirdio/netbird v0.74.3 infrastructure_files/management.json.tmpl.
    #
    # The ONE value that must NOT be baked into the Nix store is the relay HMAC
    # (`Relay.Secret`): it is left as the literal placeholder `$NB_AUTH_SECRET`
    # and rendered at activation by the netbird-management-config oneshot
    # (envsubst from the sops secret into /run/netbird-management/management.json,
    # which the container mounts). CredentialsTTL raised 24h->168h (§7).
    managementConfig = pkgs.writeText "netbird-management.json.tmpl" (builtins.toJSON {
      StoreConfig.Engine = "postgres";
      # Placeholder — rendered at activation (see netbird-management-config).
      # Provided (not left empty) so management does not generate a key and try
      # to persist it back to the read-only config file.
      DataStoreEncryptionKey = "\$NB_DATASTORE_ENC_KEY";
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
        # Placeholder — rendered at activation (see netbird-management-config).
        Secret = "\$NB_AUTH_SECRET";
      };
      # Where clients reach signal: the public nb.<zone> host on 443 (SWAG routes
      # the signalexchange gRPC service to the netbird-signal container).
      Signal = {
        Proto = "https";
        URI = "nb.${ingressZone}:443";
        Username = "";
        Password = null;
      };
      ReverseProxy = {
        TrustedHTTPProxies = [];
        TrustedHTTPProxiesCount = 0;
        TrustedPeers = ["0.0.0.0/0"];
      };
      # OIDC via PocketID. OIDCConfigEndpoint lets management self-discover the
      # issuer's endpoints; the explicit endpoints below are belt-and-suspenders
      # (verified from PocketID's /.well-known 2026-07-11).
      HttpConfig = {
        Address = "0.0.0.0:443";
        AuthIssuer = idUrl;
        AuthAudience = oidcClientId;
        AuthKeysLocation = "${idUrl}/.well-known/jwks.json";
        AuthUserIDClaim = "";
        IdpSignKeyRefreshEnabled = false;
        OIDCConfigEndpoint = "${idUrl}/.well-known/openid-configuration";
      };
      # IdP-management API integration deferred (G5): group ACLs read the JWT
      # `groups` claim directly, no PocketID API token needed.
      IdpManagerConfig.ManagerType = "none";
      # Device-code flow off (G4/§5): PocketID's device flow is unused; servers
      # enrol via setup-key, humans via the loopback PKCE browser flow.
      DeviceAuthorizationFlow.Provider = "none";
      # Interactive `netbird up` — public client + PKCE (no secret), idToken.
      PKCEAuthorizationFlow.ProviderConfig = {
        Audience = oidcClientId;
        ClientID = oidcClientId;
        ClientSecret = "";
        AuthorizationEndpoint = "${idUrl}/authorize";
        TokenEndpoint = "${idUrl}/api/oidc/token";
        Scope = "openid profile email offline_access";
        RedirectURLs = ["http://localhost:53000"];
        UseIDToken = true;
      };
    });
  in {
    options.services.netbirdServer = {
      enable = lib.mkEnableOption "self-hosted NetBird control plane (management/signal/dashboard/PocketID/relay#1) on discovery — disabled by default, see the NetBird RFC (Phase S/O are human-gated)";
      idpOnly = lib.mkEnableOption "IdP-only bring-up: start ONLY PocketID (NetBird's OIDC IdP) and declare ONLY its encryption-key secret, so a first switch-discovery cannot fail the crown-jewel hub on the not-yet-minted management/relay secrets — see docs/proposals/2026-07-11-pocketid-idp-for-netbird.md";
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      # === Always on when the module is enabled (idpOnly OR full) ============
      # PocketID is the IdP that must exist FIRST (its OIDC client is created in
      # it before management is configured), so it — and ONLY its secret — lives
      # in this unconditional block. idpOnly stops here; full mode (below) adds
      # the rest, so a first idpOnly `switch-discovery` needs only this one
      # minted secret and cannot fail the crown-jewel hub on the others (RFC §3).
      {
        # Q1: discovery force-disables podman (see discovery-containers.nix) and
        # oci-containers defaults to "podman" on stateVersion >= 22.05 — must be
        # set explicitly or these containers silently try (and fail) to use a
        # backend that's off.
        virtualisation.oci-containers.backend = "docker";

        # PocketID's at-rest encryption key. §2: the env var is ENCRYPTION_KEY
        # (confirmed against pocket-id.org); the old `pocketid_jwt_key` sops
        # label was a misnomer (not a JWT key) — renamed to
        # `netbird/pocketid_encryption_key`. Content, Phase-S human-minted:
        # `ENCRYPTION_KEY=<openssl rand -base64 32>`.
        sops.secrets."netbird/pocketid_encryption_key" = {
          inherit sopsFile;
          format = "yaml";
          key = "netbird/pocketid_encryption_key";
          mode = "0400";
          path = "/run/secrets/netbird-pocketid-encryption-key";
          restartUnits = ["docker-netbird-pocketid.service"];
        };

        virtualisation.oci-containers.containers.netbird-pocketid = {
          image = "ghcr.io/pocket-id/pocket-id:${pocketIdTag}";
          volumes = ["${dataDir}/pocket-id:/app/data"];
          environment = {
            APP_URL = idUrl;
            TRUST_PROXY = "true"; # behind SWAG (§5 — tailnet/LAN-only ingress)
          };
          environmentFiles = [
            config.sops.secrets."netbird/pocketid_encryption_key".path
          ];
          networks = ["homelab-net"];
        };
      }

      # === Full control plane (idpOnly = false) ==============================
      # management/signal/dashboard/relay#1 + their three secrets. Reached only
      # after the PocketID OIDC client and the real secrets exist (RFC §6 step 6).
      (lib.mkIf (!cfg.idpOnly) {
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
          restartUnits = ["netbird-management-config.service" "docker-netbird-management.service" "docker-netbird-relay.service"];
        };
        sops.secrets."netbird/datastore_enc_key" = {
          inherit sopsFile;
          format = "yaml";
          key = "netbird/datastore_enc_key";
          mode = "0400";
          path = "/run/secrets/netbird-datastore-enc-key";
          # Content: `NB_DATASTORE_ENC_KEY=<openssl rand -base64 32>` — encrypts
          # netbird's at-rest data store. MUST stay stable: rotating it makes the
          # existing store unreadable. Provided so management does NOT generate a
          # key and try to write it back to the read-only management.json.
          # Rendered into management.json (not env) by netbird-management-config.
          restartUnits = ["netbird-management-config.service" "docker-netbird-management.service"];
        };
        # NOTE: no netbird/oidc_client_secret secret — the NetBird OIDC client is
        # public + PKCE (RFC §5 / G4), so PocketID issues no client secret.

        # Render management.json at activation, substituting the relay HMAC from
        # the sops secret into the store template (a real secret must never be
        # baked into a world-readable /nix/store path). Ordered before — and
        # required by — the management container so it always has a fresh render
        # (/run is tmpfs, cleared each boot). Dir 0700 keeps the rendered secret
        # host-private; file 0444 lets the container read it regardless of its uid.
        systemd.services.netbird-management-config = {
          description = "Render netbird management.json with the relay HMAC from sops";
          before = ["docker-netbird-management.service"];
          requiredBy = ["docker-netbird-management.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -d -m 0700 /run/netbird-management
            # Extract the value (the sops secret is a `NB_AUTH_SECRET=<hmac>`
            # dotenv line); do NOT source it — a stray line would be executed.
            export NB_AUTH_SECRET="$(${pkgs.gnused}/bin/sed -n 's/^NB_AUTH_SECRET=//p' ${config.sops.secrets."netbird/auth_secret".path})"
            export NB_DATASTORE_ENC_KEY="$(${pkgs.gnused}/bin/sed -n 's/^NB_DATASTORE_ENC_KEY=//p' ${config.sops.secrets."netbird/datastore_enc_key".path})"
            ${pkgs.envsubst}/bin/envsubst '$NB_AUTH_SECRET $NB_DATASTORE_ENC_KEY' \
              < ${managementConfig} \
              > /run/netbird-management/management.json
            chmod 0444 /run/netbird-management/management.json
          '';
        };

        virtualisation.oci-containers.containers = {
          netbird-management = {
            image = "netbirdio/management:${netbirdTag}";
            volumes = [
              "/run/netbird-management/management.json:/etc/netbird/management.json:ro"
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
              # Q5: store engine = postgres (the DSN itself arrives via the
              # NETBIRD_STORE_ENGINE_POSTGRES_DSN env file below). All OIDC/auth
              # config lives in management.json (HttpConfig + the flow blocks) —
              # the management binary does NOT read NETBIRD_AUTH_* env vars (those
              # are the getting-started's templating vars), so none are set here.
              NETBIRD_STORE_ENGINE = "postgres";
            };
            # Only the Postgres DSN comes via env. The relay HMAC is rendered
            # into management.json by the netbird-management-config oneshot, not
            # passed as env here.
            environmentFiles = [
              config.sops.secrets."netbird/postgres_dsn".path
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
              AUTH_CLIENT_ID = oidcClientId;
              AUTH_SUPPORTED_SCOPES = "openid profile email";
              AUTH_AUDIENCE = oidcClientId;
              USE_AUTH0 = "false";
              # The SPA computes redirect_uri = window.location.origin + this.
              # The dashboard's default is `/#callback` (a URL FRAGMENT), which a
              # spec-compliant IdP like PocketID rejects (OAuth2 forbids fragments
              # in redirect_uri). Point it at a real, fragment-less 200 route that
              # loads the SPA so @axa-fr/react-oidc can process the code there;
              # `/install` is served AND is on the dashboard's own callback-context
              # allowlist. Register https://nb.<zone>/install in the PocketID client.
              # redirect_uri = window.location.origin + this. Must be:
              #  - fragment-less (PocketID/OAuth2 reject a `#` in redirect_uri —
              #    rules out the dashboard default `/#callback`), AND
              #  - the HOME route `/` — @axa-fr/react-oidc only runs the code
              #    exchange inside the app shell; standalone pages like /install
              #    load the SPA but never exchange the code (verified 2026-07-11).
              # `/` satisfies both. Register https://nb.<zone>/ in the PocketID
              # client. Silent MUST differ from redirect (@axa-fr throws if equal),
              # so silent stays /silent-auth (404 → silent renew degrades to
              # interactive re-login; harmless for login itself).
              AUTH_REDIRECT_URI = "/";
              AUTH_SILENT_REDIRECT_URI = "/silent-auth";
            };
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
      })
    ]);
  };
}
