{...}: {
  flake.modules.nixos.laptop-networking = {...}: {
    networking = {
      hostName = "laptop";
      networkmanager.enable = true;
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = true;
        checkReversePath = "loose";
        allowedTCPPorts = [
          22000 # syncthing
        ];
        allowedUDPPorts = [21027]; # syncthing discovery
      };
    };
  };
}
