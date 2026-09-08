{config, ...}: let
  uplink = "lan0";
in {
  flake.modules.nixos.apollo-networking = {lib, ...}: {
    networking = {
      hostName = "apollo";
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.${uplink}.useDHCP = true;
      nat.externalInterface = uplink;
      firewall = {
        enable = true;
        checkReversePath = "loose";
      };
    };

    # Keep DHCP and guest NAT independent of PCI numbering after hardware moves.
    systemd.network.links."10-apollo-lan" = {
      matchConfig.PermanentMACAddress = config.flake.fleet.hosts.apollo.mac;
      linkConfig = {
        NamePolicy = "";
        Name = uplink;
        WakeOnLan = "magic";
      };
    };

    services.tailscale = {
      useRoutingFeatures = lib.mkForce "client";
      extraSetFlags = lib.mkForce ["--accept-dns=true" "--accept-routes=false"];
    };
  };
}
