_: {
  flake.modules.nixos.orion-networking = {lib, ...}: {
    networking = {
      hostName = "orion";
      networkmanager.enable = true;
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = true;
        checkReversePath = "loose";
        allowedTCPPorts = [
          8080 # llama.cpp (LiteLLM routes here)
          8081
          22000
          # 80/443 closed 2026-07-01 — no consumer (P0 exposure cleanup).
          # 8642/8644 closed — hermes-agent relocated to Discovery on 2026-05-23.
        ];
        allowedUDPPorts = [21027];
      };
    };

    # Orion is permanently on the LAN; accepting Discovery's LAN /32 routes
    # diverts gateway traffic into Tailscale where the server ACL rejects it.
    services.tailscale.extraSetFlags = lib.mkForce ["--accept-dns=true" "--accept-routes=false"];
  };
}
