_: {
  flake.modules.nixos.vanguard-networking = {lib, ...}: {
    networking = {
      hostName = "vanguard";
      networkmanager.enable = false;
      useDHCP = false;
      interfaces.ens3.useDHCP = true;

      # vanguard is a multi-role node (docs/proposals/
      # 2026-07-10-vanguard-second-oracle-node.md); every role is opt-in and
      # disabled by default, and each role module opens its own port(s) under
      # its own `lib.mkIf cfg.enable` (per-interface style, matching voyager/
      # telstar) — nothing fixed here beyond break-glass SSH.
      firewall = {
        enable = true;
        checkReversePath = "loose";
      };
    };

    services.tailscale.useRoutingFeatures = lib.mkForce "client";
  };
}
