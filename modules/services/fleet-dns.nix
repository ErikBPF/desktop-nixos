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
        template IN A {
          answer "{{ .Name }} 300 IN A ${hostIp}"
        }
      }
    '';
  in {
    options.services.fleetDns = {
      enable = lib.mkEnableOption "the CoreDNS secondary fleet resolver — disabled by default, see docs/proposals/2026-07-10-vanguard-second-oracle-node.md §R1";

      upstream = lib.mkOption {
        type = lib.types.listOf lib.types.singleLineStr;
        default = ["1.1.1.1" "9.9.9.9"];
        description = "Public upstream resolvers for everything outside the fleet.ingress zones.";
      };
    };

    config = lib.mkIf cfg.enable {
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
              forward . ${lib.concatStringsSep " " cfg.upstream}
              log
              errors
            }
          '';
      };

      # Fallback resolver for fleet peers over the tailnet, not a public DNS
      # server — never opened on the public interface.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [53];
      networking.firewall.interfaces.tailscale0.allowedUDPPorts = [53];
    };
  };
}
