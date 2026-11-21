_: {
  flake.modules.nixos.endeavour-networking = _: {
    networking = {
      hostName = "endeavour";
      networkmanager = {
        enable = true;
        settings.connectivity = {
          enabled = true;
          uri = "http://nmcheck.gnome.org/check_network_status.txt";
          response = "NetworkManager is online";
          interval = 60;
        };
      };
      firewall = {
        allowedTCPPorts = [22000];
        allowedUDPPorts = [21027 22000];
      };
    };
  };
}
