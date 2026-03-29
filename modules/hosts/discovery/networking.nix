_: {
  flake.modules.nixos.discovery-networking = {lib, ...}: {
    networking = {
      hostName = "discovery";
      networkmanager.enable = true;
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = true;
        checkReversePath = "loose";
        # Default-closed: only SSH + syncthing
        allowedTCPPorts = [
          22000 # syncthing
        ];
        allowedUDPPorts = [
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
