{
  lib,
  self,
  config,
  ...
}: {
  options = {
    username = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "erik";
    };
    fullName = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "Erik Bogado";
    };
    email = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "erikbogado@gmail.com";
    };
    domain = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "pastelariadev.com";
      description = "Primary domain for fleet services (HA, k3s ingress, hermes/litellm).";
    };
    configPath = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = self + "/config";
      description = "Path to non-nix assets (wallpapers, keyboard, quickshell QML)";
    };

    # Fleet addressing SSOT (RFC 2026-06-29 P1). Define each host once here;
    # consumers (justfile `ip_*`, host networking, homelab-iac reservations +
    # AdGuard DNS) read the published `flake.fleet` artifact (fleet.json) rather
    # than re-encoding IPs. Subnet is 192.168.10.0/24 (gateway .1, UDM).
    fleet.hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            ip = lib.mkOption {
              type = lib.types.nullOr lib.types.singleLineStr;
              default = null;
              description = "Primary IPv4 (LAN, or public for voyager). null = roaming/tailnet-only (laptop).";
            };
            mac = lib.mkOption {
              type = lib.types.nullOr lib.types.singleLineStr;
              default = null;
              description = "Primary-NIC MAC used for the DHCP reservation; null when unknown/unpinned.";
            };
            role = lib.mkOption {
              type = lib.types.enum ["server" "workstation" "laptop" "appliance"];
              description = "Functional role. appliance = non-NixOS device tracked for addressing only (e.g. HAOS VM).";
            };
            tailscaleIp = lib.mkOption {
              type = lib.types.nullOr lib.types.singleLineStr;
              default = null;
              description = "Stable tailnet IP, when one is documented.";
            };
          };
        }
      );
      description = "Fleet host addressing — the single source for IP/MAC/role across repos.";
      default = {
        # NixOS hosts (managed by this flake's nixosConfigurations).
        discovery = {
          ip = "192.168.10.210";
          mac = "64:51:06:1a:f8:1a";
          role = "server";
          tailscaleIp = "100.76.140.121";
        };
        orion = {
          ip = "192.168.10.220";
          mac = "b4:2e:99:92:4f:8b";
          role = "server";
        };
        kepler = {
          ip = "192.168.10.230";
          mac = "74:56:3c:47:d1:77";
          role = "server";
        };
        pathfinder = {
          ip = "192.168.10.125";
          mac = "54:bf:64:28:cb:2e";
          role = "workstation";
        };
        archinaut = {
          # WiFi-only (wlan0); wired NIC retired (see archinaut memory).
          ip = "192.168.10.225";
          mac = "b8:27:eb:15:7e:48";
          role = "server";
        };
        voyager = {
          # Public Oracle Cloud VM; no LAN MAC reservation.
          ip = "129.148.45.145";
          role = "server";
        };
        laptop = {
          # Roaming — Tailscale-only, no fixed LAN reservation.
          role = "laptop";
        };
        # Non-NixOS device tracked for addressing only: Home Assistant OS,
        # a KVM guest on discovery (MAC from modules/hosts/discovery/haos.nix).
        homeassistant = {
          ip = "192.168.10.115";
          mac = "52:54:00:d6:a5:ce";
          role = "appliance";
        };
      };
    };

    # Domains/hostnames SSOT (RFC 2026-06-29 P2) — the DNS/edge layer only.
    # Per-service SWAG routes (container backends on discovery) stay servarr-owned
    # (SRP D1/D2); lab *.k8s hostnames live in homelab-gitops. This source covers
    # only the fleet-level facts: ingress zones + public + cross-host backends.
    fleet.ingress = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            zone = lib.mkOption {
              type = lib.types.singleLineStr;
              description = "Wildcard DNS zone; *.<zone> resolves to the fronting host's IP.";
            };
            host = lib.mkOption {
              type = lib.types.singleLineStr;
              description = "Fleet host (key in fleet.hosts) running the reverse proxy for the zone.";
            };
          };
        }
      );
      description = "Home ingress zones. Consumers resolve *.<zone> → fleet.hosts.<host>.ip.";
      default = {
        homelab = {
          zone = "homelab.pastelariadev.com";
          host = "discovery";
        };
        # *.ai (kepler/AI) removed: it's a lab/AI concern — lab hostnames live in
        # homelab-gitops (D2), and the wildcard had no live backend.
      };
    };

    fleet.services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            fqdn = lib.mkOption {
              type = lib.types.nullOr lib.types.singleLineStr;
              default = null;
              description = "Edge FQDN for scope=public (Cloudflare). null for home services (reached via *.<ingress zone>).";
            };
            backend = lib.mkOption {
              description = "Where the reverse proxy forwards.";
              type = lib.types.submodule {
                options = {
                  host = lib.mkOption {
                    type = lib.types.singleLineStr;
                    description = "Fleet host (key in fleet.hosts) the proxy forwards to.";
                  };
                  port = lib.mkOption {type = lib.types.port;};
                };
              };
            };
            scope = lib.mkOption {
              type = lib.types.enum ["home" "public"];
              default = "home";
              description = "home = LAN via *.<ingress zone>/SWAG; public = also exposed via Cloudflare tunnel (needs fqdn).";
            };
          };
        }
      );
      description = "Fleet-level service routing: public (Cloudflare) + cross-host home backends. Single-host container routes stay servarr-owned.";
      default = {
        ha = {
          fqdn = "ha.pastelariadev.com";
          backend = {
            host = "homeassistant";
            port = 8123;
          };
          scope = "public";
        };
        # kepler-backed services (rpg, immich, openwebui) removed — kepler is the
        # lab/AI host; its service hostnames belong to homelab-gitops (D2), and
        # rpg/*.ai had no live backend. Re-add here only if a service becomes a
        # genuine home (non-lab) cross-host fact.
        n8n = {
          backend = {
            host = "orion";
            port = 5678;
          };
        };
      };
    };
  };

  # Publish the fleet table as a flake output so it can be pinned to disk:
  #   nix eval .#fleet --json | jq . > fleet.json   (`just fleet-json`)
  # Vendored by homelab-iac (jsondecode) on a deliberate bump — never read live.
  config.flake.fleet = {inherit (config.fleet) hosts ingress services;};
}
