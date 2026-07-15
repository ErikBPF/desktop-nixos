# Secondary fleet DNS (R1, docs/proposals/2026-07-10-vanguard-second-oracle-node.md).
# AdGuard on discovery is today the ONLY internal resolver — discovery down
# means no fleet-name resolution (public fallback only). This registers a
# light CoreDNS instance (intended host: vanguard) that SERVES each
# fleet.ingress zone locally (not by forwarding to discovery, which would fail
# in exactly the scenario this exists for) and forwards everything else to
# public upstreams. Add the host's tailnet IP to the homelab-iac
# tailscale/dns MagicDNS nameserver list (after discovery's) to actually wire
# it in as a fallback resolver — that's a separate repo, written not applied.
#
# DISABLED BY DEFAULT (services.fleetDns.enable = false).
{config, ...}: let
  fleet = config.flake.fleet;
in {
  flake.modules.nixos.fleet-dns = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.fleetDns;

    # One CoreDNS server block per fleet.ingress zone: `template` answers every
    # A query CoreDNS routes here (i.e. anything matching `<zone>` or
    # `*.<zone>`, since CoreDNS dispatches by zone suffix) with the zone's
    # fronting host's IP — a static synthesis of the same wildcard SWAG serves,
    # so it works even when that host's own resolver is down.
    zoneBlock = zone: hostIp: ''
      ${zone} {
        bind ${cfg.interface}
        template IN A {
          answer "{{ .Name }} 300 IN A ${hostIp}"
        }
        template IN AAAA {
          rcode NOERROR
        }
      }
    '';
  in {
    options.services.fleetDns = {
      enable = lib.mkEnableOption "the CoreDNS secondary fleet resolver — disabled by default, see docs/proposals/2026-07-10-vanguard-second-oracle-node.md §R1";

      interface = lib.mkOption {
        type = lib.types.enum ["tailscale0" "enp5s0"];
        default = "tailscale0";
        description = "Interface on which CoreDNS listens and the firewall permits DNS.";
      };

      upstream = lib.mkOption {
        type = lib.types.listOf lib.types.singleLineStr;
        default = ["1.1.1.1" "9.9.9.9"];
        description = "Ordered upstream resolvers for everything outside the fleet.ingress zones.";
      };

      sequentialUpstream = lib.mkEnableOption "ordered CoreDNS upstream failover";

      queryLog = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether CoreDNS logs every query.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.upstream != [];
          message = "services.fleetDns.upstream must not be empty";
        }
        {
          assertion =
            !cfg.sequentialUpstream
            || (builtins.length cfg.upstream
              >= 2
              && builtins.head cfg.upstream == fleet.hosts.discovery.ip);
          message = "sequential fleet DNS requires discovery first and at least one fallback";
        }
      ];

      services.coredns = {
        enable = true;
        config =
          lib.concatStrings (
            lib.mapAttrsToList
            (_: ingress: zoneBlock ingress.zone fleet.hosts.${ingress.host}.ip)
            fleet.ingress
          )
          + ''
            . {
              bind ${cfg.interface}
              ${lib.optionalString (!cfg.sequentialUpstream) "forward . ${lib.concatStringsSep " " cfg.upstream}"}
              ${lib.optionalString cfg.sequentialUpstream ''
              forward . ${lib.concatStringsSep " " cfg.upstream} {
                policy sequential
              }
            ''}
              ${lib.optionalString cfg.queryLog "log"}
              errors
            }
          '';
      };

      # Wait for the owner of the reviewed bind interface. The default tailnet
      # role keeps its original tailscaled ordering; the LAN role waits for
      # network-online. Restart retries the bind if address assignment lags.
      systemd.services.coredns = {
        after =
          if cfg.interface == "tailscale0"
          then ["tailscaled.service"]
          else ["network-online.target"];
        wants = lib.optional (cfg.interface != "tailscale0") "network-online.target";
        serviceConfig.RestartSec = "3s";
      };

      # Permit DNS only on the selected reviewed interface, never globally.
      networking.firewall.interfaces.${cfg.interface} = {
        allowedTCPPorts = [53];
        allowedUDPPorts = [53];
      };
    };
  };
}
