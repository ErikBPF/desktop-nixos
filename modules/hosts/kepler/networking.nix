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
          111 # rpcbind (required by NFS clients even with NFSv4)
          2049 # NFS
          4000 # rpc.statd (pinned)
          4001 # lockd (pinned)
          4002 # rpc.mountd (pinned)
          445 # Samba SMB (NetBIOS disabled — port 445 only)
        ];
        allowedUDPPorts = [
          21027 # syncthing discovery
          111 # rpcbind UDP
          4000 # statd UDP
          4001 # lockd UDP
        ];
      };
    };

    # Tailscale client — no subnet routing needed (not the gateway host)
    services.tailscale = {
      useRoutingFeatures = lib.mkForce "client";
    };
  };
}
