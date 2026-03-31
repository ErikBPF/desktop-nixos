_: {
  flake.modules.nixos.kepler-networking = {lib, ...}: {
    networking = {
      hostName = "kepler";

      # Headless server — no NetworkManager.
      networkmanager.enable = false;
      useDHCP = false;

      # Realtek r8169 NIC — confirmed via lspci on live ISO
      interfaces.enp5s0.useDHCP = true;

      firewall = {
        enable = true;
        checkReversePath = "loose";
        allowedTCPPorts = [
          22 # SSH (already open via openssh module, explicit for clarity)
          22000 # syncthing
          2049 # NFS
          445 # Samba SMB (NetBIOS disabled — port 445 only)
        ];
        allowedUDPPorts = [
          21027 # syncthing discovery
        ];
      };
    };

    # Tailscale client — no subnet routing needed (not the gateway host)
    services.tailscale = {
      useRoutingFeatures = lib.mkForce "client";
    };
  };
}
