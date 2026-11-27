_: {
  flake.modules.nixos.challenger-networking = _: {
    networking = {
      hostName = "challenger";
      networkmanager = {
        enable = true;
        settings.connectivity = {
          enabled = true;
          uri = "http://nmcheck.gnome.org/check_network_status.txt";
          response = "NetworkManager is online";
          interval = 60;
        };
      };
      # DHCP; the wired NIC is pinned to 192.168.10.201 by the UniFi
      # reservation generated from fleet.hosts.challenger.
      firewall = {
        allowedTCPPorts = [22000];
        allowedUDPPorts = [21027 22000];
      };
    };
  };
}
