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
        ];
        allowedUDPPorts = [
          53 # DNS
          21027 # syncthing discovery
        ];
      };
    };

    # Tailscale subnet router (override client default from profile-base)
    services.tailscale = {
      useRoutingFeatures = lib.mkForce "server";
      extraUpFlags = [
        "--advertise-routes=192.168.10.0/24"
      ];
    };
  };
}
