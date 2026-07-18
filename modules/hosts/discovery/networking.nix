{config, ...}: let
  # Self IP from the fleet SSOT (modules/meta.nix) — don't re-type the literal.
  selfIp = config.fleet.hosts.discovery.ip;
in {
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
          8091 # HA harness dry-run API (bearer-authenticated)
          22000 # syncthing
          32400 # Plex Media Server
        ];
        allowedUDPPorts = [
          53 # DNS
          21027 # syncthing discovery
        ];
      };
    };

    # Disable TCP segmentation offload on the onboard Intel NIC (eno1). Its
    # e1000e driver periodically wedges the TX ring — `Detected Hardware Unit
    # Hang` (TDH/TDT desync), which kills the whole host's network until a
    # reboot. This was P2-1, the root cause of discovery's "intermittent network
    # loss" (see docs/implemented/2026-06-29-discovery-resilience-fixes.md). The
    # hang is triggered by the TSO/GSO offload path; moving segmentation to the
    # kernel avoids it, at a few % of one core under sustained line-rate transfer
    # (negligible at this host's gigabit workload). GRO (receive) left on — the
    # hang is a transmit bug. udev .link matched by MAC so it applies before the
    # interface is enslaved to br0; takes effect on next device add / boot.
    #
    # CRITICAL: .link files are first-match-wins (not merged). At priority 10 this
    # matches the NIC before systemd's built-in 99-default.link, so it MUST carry
    # the naming policy itself — otherwise the NIC is never renamed to eno1, stays
    # `eth0`, and the scripted br0 bridge (which enslaves eno1) fails to build →
    # total network loss. The NamePolicy below mirrors 99-default.link so eno1
    # naming still happens. (Regression fixed 2026-07-09 after a boot lost the
    # NIC name and took the whole host offline.)
    systemd.network.links."10-eno1-no-tso" = {
      matchConfig.PermanentMACAddress = "64:51:06:1a:f8:1a";
      linkConfig = {
        NamePolicy = "keep kernel database onboard slot path";
        AlternativeNamesPolicy = "database onboard slot path";
        MACAddressPolicy = "persistent";
        TCPSegmentationOffload = false;
        TCP6SegmentationOffload = false;
        GenericSegmentationOffload = false;
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
        # selfIp (.210) from fleet SSOT; .1 = UDM, .2 = swOS switch (not fleet hosts).
        "--advertise-routes=${selfIp}/32,192.168.10.1/32,192.168.10.2/32"
      ];
    };
  };
}
