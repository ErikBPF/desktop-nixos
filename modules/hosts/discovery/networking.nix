_: {
  flake.modules.nixos.discovery-networking = {lib, ...}: {
    networking = {
      hostName = "discovery";

      # AdGuard (local container on .210) is the primary resolver. fallbackDns
      # (services.resolved below) keeps DNS alive at boot / whenever AdGuard is
      # briefly down, so the container DNS race that took hermes down can't
      # recur. Tailscale keeps accept-dns ON → *.taild71d3.ts.net still routes
      # to MagicDNS (split-DNS preserved).
      nameservers = ["192.168.10.210"];

      # Headless server — use systemd-networkd style config, not NetworkManager.
      # NetworkManager is disabled to avoid fighting with the declarative bridge.
      networkmanager.enable = false;
      useDHCP = false; # set per-interface below

      # br0: LAN bridge — eno1 enslaved, bridge gets DHCP.
      # Required for HAOS KVM VM to appear on the LAN with its own MAC address.
      bridges.br0.interfaces = ["eno1"];
      interfaces.eno1.useDHCP = false;
      interfaces.br0.useDHCP = true;

      firewall = {
        enable = true;
        checkReversePath = "loose";
        # Default-closed: only SSH + syncthing
        allowedTCPPorts = [
          53 # DNS
          80 # HTTP
          443 # HTTPS
          22000 # syncthing
          32400 # Plex Media Server
        ];
        allowedUDPPorts = [
          53 # DNS
          21027 # syncthing discovery
        ];
      };
    };

    # Resolution survives AdGuard being down (boot window / outage): resolved
    # falls back to the UDM + public DNS rather than hard-failing.
    services.resolved.settings.Resolve.FallbackDNS = "192.168.10.1 1.1.1.1 9.9.9.9";

    # Tailscale subnet router (override client default from profile-base).
    # Advertises /32s for the LAN-only hosts tailnet devices need to reach (the
    # swOS switch, the UDM) that can't run Tailscale, plus the swag ingress.
    # Narrowed from 192.168.10.0/24: a /24 subnet route poisons on-LAN hosts
    # that also run --accept-routes (orion/kepler), which pull their own subnet
    # into Tailscale's table 52 and blackhole the LAN. Reach is gated by the
    # tailnet ACL (admin devices only); SNAT (server default) means no return
    # route is needed on the UDM. Approved declaratively in homelab-iac.
    services.tailscale = {
      useRoutingFeatures = lib.mkForce "server";
      # extraSetFlags (not extraUpFlags): `tailscale set` re-applies on every
      # activation, so changing the route takes effect on switch. extraUpFlags
      # only runs at first connect, so it wouldn't update an already-up node.
      extraSetFlags = [
        "--advertise-routes=192.168.10.210/32,192.168.10.1/32,192.168.10.2/32"
      ];
    };
  };
}
