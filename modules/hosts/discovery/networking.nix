_: {
  flake.modules.nixos.discovery-networking = {lib, ...}: {
    networking = {
      hostName = "discovery";

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

    # Tailscale subnet router (override client default from profile-base).
    # Advertises the whole LAN so tailnet devices reach LAN-only hosts (the
    # swOS switches, the UDM, printer, IoT) that can't run Tailscale. Reach is
    # gated by the tailnet ACL (admin devices only); SNAT (server default) means
    # no return route is needed on the UDM. Approved declaratively in homelab-iac.
    services.tailscale = {
      useRoutingFeatures = lib.mkForce "server";
      # extraSetFlags (not extraUpFlags): `tailscale set` re-applies on every
      # activation, so widening the route takes effect on switch. extraUpFlags
      # only runs at first connect, so it wouldn't update an already-up node.
      extraSetFlags = [
        "--advertise-routes=192.168.10.0/24"
      ];
    };
  };
}
