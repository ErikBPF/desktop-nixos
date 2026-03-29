_: {
  flake.modules.nixos.orion-networking = _: {
    networking = {
      hostName = "orion";
      networkmanager.enable = true;
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = true;
        checkReversePath = "loose";
        allowedTCPPorts = [
          80
          443
          22000
        ];
        allowedUDPPorts = [21027];
      };
    };
  };
}
