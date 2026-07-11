_: {
  flake.modules.nixos.vanguard-networking = {lib, ...}: {
    networking = {
      hostName = "vanguard";
      networkmanager.enable = false;
      # Name-agnostic DHCP: dhcpcd on ALL interfaces regardless of what the NIC
      # is named. The ens3-specific form worked on voyager (nixpkgs 25.11) but
      # left vanguard dark on 26.11 — a newer systemd/kernel names the NIC
      # something other than `ens3`, so an interface-specific rule targets a
      # dead name (cf. the discovery eno1 .link-naming outage). `useDHCP = true`
      # sidesteps the naming entirely.
      useDHCP = true;

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

    # Serial console (Oracle) — matches voyager's cmdline; gives a break-glass
    # path via the Oracle serial console if a boot ever comes up off-network.
    boot.kernelParams = ["console=ttyS0,115200n8" "console=tty0"];

    services.tailscale.useRoutingFeatures = lib.mkForce "client";
  };
}
