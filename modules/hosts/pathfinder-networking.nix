{...}: {
  flake.modules.nixos.pathfinder-networking = {...}: {
    networking = {
      hostName = "pathfinder";
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
