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
          8080 # llama.cpp (LiteLLM routes here)
          8081
          22000
          # 80/443 closed 2026-07-01 — no consumer (P0 exposure cleanup).
          # 8642/8644 closed — hermes-agent relocated to Discovery on 2026-05-23.
        ];
        allowedUDPPorts = [21027];
      };
    };
  };
}
