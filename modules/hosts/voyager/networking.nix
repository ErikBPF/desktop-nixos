_: {
  flake.modules.nixos.voyager-networking = {lib, ...}: {
    networking = {
      hostName = "voyager";
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.ens3.useDHCP = true;

      firewall = {
        enable = true;
        checkReversePath = "loose";
        # The restic REST receiver is published by rootless Podman, but should
        # only be reachable across the tailnet. Public SSH remains available for
        # break-glass Oracle access; fleet SSH still moves to port 2222.
        interfaces.tailscale0.allowedTCPPorts = [8000];
      };
    };

    services.tailscale.useRoutingFeatures = lib.mkForce "client";
  };
}
