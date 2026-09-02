_: {
  flake.modules.nixos.apollo-networking = {lib, ...}: {
    networking = {
      hostName = "apollo";
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.enp6s0.useDHCP = true;
      firewall = {
        enable = true;
        checkReversePath = "loose";
      };
    };

    services.tailscale = {
      useRoutingFeatures = lib.mkForce "client";
      extraSetFlags = lib.mkForce ["--accept-dns=true" "--accept-routes=false"];
    };
  };
}
