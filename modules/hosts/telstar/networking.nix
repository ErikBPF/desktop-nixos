_: {
  flake.modules.nixos.telstar-networking = {lib, ...}: {
    networking = {
      hostName = "telstar";
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.ens3.useDHCP = true;

      # telstar exposes personal projects to the public internet, so public
      # ingress is deliberately scoped here as it is added. Until then the host
      # is reachable only by break-glass public SSH and over the tailnet; no
      # project ports are open yet. Add public service ports explicitly (and the
      # matching Oracle security-list ingress rule in homelab-iac) per project.
      firewall = {
        enable = true;
        checkReversePath = "loose";
      };
    };

    services.tailscale.useRoutingFeatures = lib.mkForce "client";
  };
}
