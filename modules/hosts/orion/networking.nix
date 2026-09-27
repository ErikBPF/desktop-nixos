_: {
  flake.modules.nixos.orion-networking = {
    lib,
    pkgs,
    ...
  }: {
    networking = {
      hostName = "orion";
      networkmanager.enable = true;
      networkmanager.dns = "systemd-resolved";
      firewall = {
        enable = true;
        checkReversePath = "loose";
        interfaces.tailscale0.allowedTCPPorts = [8085 8087];
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

    # Wake-on-LAN: re-arm the NIC register on every boot. The register is lost
    # across a full power cycle, and NetworkManager's `wake-on-lan` connection
    # property only takes effect once a profile is active — a boot oneshot is
    # the simplest guarantee for remote wake.
    systemd.services.orion-wol = {
      description = "Enable Wake-on-LAN (magic packet) on enp4s0";
      wantedBy = ["multi-user.target"];
      after = ["network-pre.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.ethtool}/bin/ethtool -s enp4s0 wol g";
      };
    };

    # Orion is permanently on the LAN; accepting Discovery's LAN /32 routes
    # diverts gateway traffic into Tailscale where the server ACL rejects it.
    services.tailscale.extraSetFlags = lib.mkForce ["--accept-dns=true" "--accept-routes=false"];
  };
}
