_: {
  flake.modules.nixos.endeavour-networking = _: {
    networking = {
      hostName = "endeavour";
      networkmanager.enable = true;
      firewall = {
        allowedTCPPorts = [22000];
        allowedUDPPorts = [21027 22000];
      };
    };
  };
}
